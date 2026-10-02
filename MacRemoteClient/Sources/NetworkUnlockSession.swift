import Foundation
import Network

final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<T, Error>?
    private var continuation: CheckedContinuation<T, Error>?
    private var timer: Task<Void, Never>?
    private var registered = false

    func wait(timeout: TimeInterval) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if registered {
                    lock.unlock()
                    continuation.resume(throwing: UnlockSessionError.protocolError)
                    return
                }
                registered = true
                if Task.isCancelled && outcome == nil { outcome = .failure(UnlockSessionError.cancelled) }
                if let outcome {
                    lock.unlock()
                    continuation.resume(with: outcome)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                let timer = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                    if !Task.isCancelled { self?.resume(throwing: UnlockSessionError.timedOut) }
                }
                lock.lock()
                if outcome == nil { self.timer = timer } else { timer.cancel() }
                lock.unlock()
            }
        } onCancel: {
            resume(throwing: UnlockSessionError.cancelled)
        }
    }

    func resume(returning value: T) { complete(.success(value)) }
    func resume(throwing error: Error) { complete(.failure(error)) }

    private func complete(_ result: Result<T, Error>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result
        let continuation = self.continuation
        self.continuation = nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
        continuation?.resume(with: result)
    }
}

struct UnlockHandshake: Sendable, Equatable {
    let serverId: String?
    let challenge: Data?
    let unlockAvailable: Bool
}

enum UnlockSessionError: Error, Equatable {
    case connectionFailed, localNetworkDenied, timedOut, closed, cancelled, protocolError
}

protocol UnlockSession: AnyObject, Sendable {
    var endpointName: String? { get }
    func open(timeout: TimeInterval) async throws -> UnlockHandshake
    func sendUnlock(signature: Data, timeout: TimeInterval) async throws -> (success: Bool, code: UnlockResultCode?)
    func close()
}

enum FrameParser {
    static func length(_ data: Data) throws -> Int {
        guard data.count == 4 else { throw UnlockSessionError.protocolError }
        let value = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard value > 0, value <= UnlockWire.maxFrameBytes else { throw UnlockSessionError.protocolError }
        return Int(value)
    }
}

final class NetworkUnlockSession: UnlockSession, @unchecked Sendable {
    let endpointName: String?
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.macremote.unlock.session")
    private let lock = NSLock()
    private var closed = false
    private var opened = false
    private var unlockSendStarted = false
    private let ready = OneShot<Void>()
    private let handshake = OneShot<UnlockHandshake>()
    private let result = OneShot<UnlockResponse>()
    private var skippedBeforeHandshake = 0
    private var inResultPhase = false

    private struct UnlockResponse: Sendable {
        let success: Bool
        let code: UnlockResultCode?
    }

    init(endpoint: NWEndpoint, name: String? = nil) {
        endpointName = name
        connection = NWConnection(to: endpoint, using: .tcp)
    }

    func open(timeout: TimeInterval) async throws -> UnlockHandshake {
        let mayOpen = lock.withLock {
            let value = !opened && !closed
            if value { opened = true }
            return value
        }
        guard mayOpen else { throw UnlockSessionError.protocolError }
        connection.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
        connection.start(queue: queue)
        do {
            try await ready.wait(timeout: timeout)
            readFrame()
            return try await handshake.wait(timeout: timeout)
        } catch {
            close()
            throw error
        }
    }

    func sendUnlock(signature: Data, timeout: TimeInterval) async throws -> (success: Bool, code: UnlockResultCode?) {
        let maySend = lock.withLock {
            let value = opened && !closed && !unlockSendStarted
            if value { unlockSendStarted = true; inResultPhase = true }
            return value
        }
        guard maySend else { throw UnlockSessionError.protocolError }
        do {
            let frame = try MessageFrame.encode(RemoteMessage.unlock(signature: signature))
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.result.resume(throwing: UnlockSessionError.connectionFailed) }
            })
            let response = try await result.wait(timeout: timeout)
            return (response.success, response.code)
        } catch {
            close()
            throw error
        }
    }

    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        lock.unlock()
        ready.resume(throwing: UnlockSessionError.closed)
        handshake.resume(throwing: UnlockSessionError.closed)
        result.resume(throwing: UnlockSessionError.closed)
        connection.cancel()
    }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready: ready.resume(returning: ())
        case .waiting(let error), .failed(let error):
            let denied = connection.currentPath?.unsatisfiedReason == .localNetworkDenied
            let mapped: UnlockSessionError = denied ? .localNetworkDenied : .connectionFailed
            if case .failed = state { fail(mapped) }
            else if denied { fail(mapped) }
            _ = error
        case .cancelled: fail(.connectionFailed)
        default: break
        }
    }

    private func fail(_ error: UnlockSessionError) {
        ready.resume(throwing: error)
        handshake.resume(throwing: error)
        result.resume(throwing: error)
    }

    private func readExact(_ count: Int, accumulated: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, complete, error in
            guard let self else { return }
            if error != nil || complete { completion(.failure(UnlockSessionError.connectionFailed)); return }
            var bytes = accumulated
            if let data { bytes.append(data) }
            if bytes.count == count { completion(.success(bytes)) }
            else { self.readExact(count, accumulated: bytes, completion: completion) }
        }
    }

    private func readFrame() {
        guard !lock.withLock({ closed }) else { return }
        readExact(4) { [weak self] header in
            guard let self else { return }
            do {
                let length = try FrameParser.length(header.get())
                self.readExact(length) { [weak self] body in
                    guard let self else { return }
                    switch body {
                    case .failure: self.fail(.connectionFailed)
                    case .success(let bytes): self.handleFrame(bytes)
                    }
                }
            } catch { self.fail(.protocolError); self.close() }
        }
    }

    private func handleFrame(_ bytes: Data) {
        guard !lock.withLock({ closed }) else { return }
        guard let message = try? MessageFrame.decode(bytes, as: ServerMessage.self) else {
            fail(.protocolError)
            close()
            return
        }
        switch message {
        case .connected(_, _, let challenge, let available, let serverId):
            handshake.resume(returning: UnlockHandshake(serverId: serverId, challenge: challenge, unlockAvailable: available))
        case .unlockResult(let success, _, let code):
            result.resume(returning: UnlockResponse(success: success, code: code))
        default:
            lock.lock()
            if !inResultPhase { skippedBeforeHandshake += 1 }
            let tooMany = skippedBeforeHandshake >= 8 && !inResultPhase
            lock.unlock()
            if tooMany { fail(.protocolError); close(); return }
        }
        readFrame()
    }
}

struct UnlockCandidate: Sendable {
    let name: String
    let endpoint: NWEndpoint
}

protocol UnlockServiceBrowsing: Sendable {
    func browse(maxDuration: TimeInterval, preferredName: String) async throws -> [UnlockCandidate]
}

enum UnlockLocatorError: Error, Equatable {
    case macNotFound, localNetworkDenied
}

final class NetworkUnlockBrowser: UnlockServiceBrowsing, @unchecked Sendable {
    func browse(maxDuration: TimeInterval, preferredName: String) async throws -> [UnlockCandidate] {
        let browser = NWBrowser(for: .bonjour(type: NetworkConstants.serviceType, domain: NetworkConstants.serviceDomain), using: .tcp)
        let queue = DispatchQueue(label: "com.macremote.unlock.browser")
        let finish = OneShot<[UnlockCandidate]>()
        let collector = BrowserCollector()
        browser.browseResultsChangedHandler = { results, _ in
            let candidates = results.map { result -> UnlockCandidate in
                let name: String
                if case .service(let serviceName, _, _, _) = result.endpoint { name = serviceName }
                else { name = result.endpoint.debugDescription }
                return UnlockCandidate(name: name, endpoint: result.endpoint)
            }
            collector.set(candidates)
            if candidates.contains(where: { $0.name == preferredName }) {
                queue.asyncAfter(deadline: .now() + 0.5) { finish.resume(returning: collector.get()) }
            }
        }
        browser.stateUpdateHandler = { state in
            switch state {
            case .waiting(let error), .failed(let error):
                if case .dns(let code) = error, Int(code) == -65570 { finish.resume(throwing: UnlockLocatorError.localNetworkDenied) }
            default: break
            }
        }
        browser.start(queue: queue)
        defer { browser.cancel() }
        do { return try await finish.wait(timeout: maxDuration) }
        catch UnlockSessionError.timedOut { return collector.get() }
    }
}

private final class BrowserCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var candidates: [UnlockCandidate] = []
    func set(_ value: [UnlockCandidate]) { lock.lock(); candidates = value; lock.unlock() }
    func get() -> [UnlockCandidate] { lock.lock(); defer { lock.unlock() }; return candidates }
}

final class UnlockMacLocator: @unchecked Sendable {
    private let browser: UnlockServiceBrowsing
    private let makeSession: @Sendable (UnlockCandidate) -> UnlockSession
    private let now: @Sendable () -> Date

    init(browser: UnlockServiceBrowsing, makeSession: @escaping @Sendable (UnlockCandidate) -> UnlockSession, now: @escaping @Sendable () -> Date = { Date() }) {
        self.browser = browser
        self.makeSession = makeSession
        self.now = now
    }

    func locate(target: UnlockTarget) async throws -> (UnlockSession, UnlockHandshake) {
        let deadline = now().addingTimeInterval(8)
        let candidates = try await browser.browse(maxDuration: min(4, max(0, deadline.timeIntervalSince(now()))), preferredName: target.displayName)
        let ordered = candidates.filter { $0.name == target.displayName } + candidates.filter { $0.name != target.displayName }
        var attempts = 0
        var denied = 0
        for candidate in ordered where deadline > now() {
            try Task.checkCancellation()
            let session = makeSession(candidate)
            attempts += 1
            do {
                let handshake = try await withTaskCancellationHandler {
                    try await session.open(timeout: min(3, deadline.timeIntervalSince(now())))
                } onCancel: {
                    session.close()
                }
                try Task.checkCancellation()
                if handshake.serverId == target.serverId { return (session, handshake) }
                session.close()
            } catch {
                session.close()
                if error is CancellationError || error as? UnlockSessionError == .cancelled { throw CancellationError() }
                if error as? UnlockSessionError == .localNetworkDenied { denied += 1 }
            }
        }
        try Task.checkCancellation()
        throw attempts > 0 && attempts == denied ? UnlockLocatorError.localNetworkDenied : .macNotFound
    }
}
