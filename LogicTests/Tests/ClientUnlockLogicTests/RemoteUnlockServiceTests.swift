import Foundation
import Testing
@testable import ClientUnlockLogic

private let testTarget = UnlockTarget(serverId: "mac", displayName: "Desk", pairedAt: Date(timeIntervalSince1970: 1))
private let testSnapshot = PairingSnapshot(token: Data([1, 2, 3]), target: testTarget)
private let testHandshake = UnlockHandshake(serverId: "mac", challenge: Data([4, 5]), unlockAvailable: true)
private enum TestError: Error { case failed }

private final class Gate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pending { lock.unlock(); continuation.resume(with: pending) }
            else { self.continuation = continuation; lock.unlock() }
        }
    }
    func finish(_ result: Result<T, Error>) {
        lock.lock()
        if let continuation { self.continuation = nil; lock.unlock(); continuation.resume(with: result) }
        else { pending = result; lock.unlock() }
    }
}

private final class FakePairing: PairingSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: PairingSnapshot?
    private var error = false
    var cancelOnSecondRead = false
    private var reads = 0
    init(_ value: PairingSnapshot? = testSnapshot) { self.value = value }
    func snapshot() throws -> PairingSnapshot? {
        let result = try lock.withLock { () throws -> PairingSnapshot? in
            reads += 1
            if error { throw TestError.failed }
            return value
        }
        if cancelOnSecondRead && lock.withLock({ reads == 2 }) { withUnsafeCurrentTask { $0?.cancel() } }
        return result
    }
    func set(_ value: PairingSnapshot?) { lock.withLock { self.value = value } }
    func fail() { lock.withLock { error = true } }
}

private final class FakeSession: UnlockSession, @unchecked Sendable {
    let endpointName: String? = "Desk"
    var handshake = testHandshake
    var openError: UnlockSessionError?
    var sendError: UnlockSessionError?
    var response: (Bool, UnlockResultCode?) = (true, .verified)
    var openGate: Gate<UnlockHandshake>?
    var sendGate: Gate<(Bool, UnlockResultCode?)>?
    private let lock = NSLock()
    private var opens = 0, sends = 0, closes = 0
    private var sent: Data?
    var counts: (Int, Int, Int) { lock.withLock { (opens, sends, closes) } }
    var signature: Data? { lock.withLock { sent } }
    func open(timeout: TimeInterval) async throws -> UnlockHandshake {
        lock.withLock { opens += 1 }
        if let openGate { return try await openGate.wait() }
        if let openError { throw openError }
        return handshake
    }
    func sendUnlock(signature: Data, timeout: TimeInterval) async throws -> (success: Bool, code: UnlockResultCode?) {
        lock.withLock { sends += 1; sent = signature }
        if let sendGate { let result = try await sendGate.wait(); return (result.0, result.1) }
        if let sendError { throw sendError }
        return response
    }
    func close() { lock.withLock { closes += 1 } }
}

private final class FakeLocator: UnlockSessionLocating, @unchecked Sendable {
    let session: FakeSession
    var error: UnlockLocatorError?
    var gate: Gate<(UnlockSession, UnlockHandshake)>?
    var cancelOnReturn = false
    init(_ session: FakeSession) { self.session = session }
    func locate(target: UnlockTarget) async throws -> (UnlockSession, UnlockHandshake) {
        if let gate { return try await gate.wait() }
        if let error { throw error }
        if cancelOnReturn { withUnsafeCurrentTask { $0?.cancel() } }
        return (session, session.handshake)
    }
}

private final class FakeAuthenticator: DeviceOwnerAuthenticating, @unchecked Sendable {
    var error: AuthenticationError?
    var gate: Gate<Void>?
    private let lock = NSLock()
    private var calls = 0, cancellations = 0
    var counts: (Int, Int) { lock.withLock { (calls, cancellations) } }
    func authenticate(reason: String) async throws {
        lock.withLock { calls += 1 }
        if let gate { try await gate.wait() }
        if let error { throw error }
    }
    func cancel() { lock.withLock { cancellations += 1 }; gate?.finish(.failure(AuthenticationError.cancelled)) }
}

private func fixture(_ pairing: FakePairing = FakePairing(), _ session: FakeSession = FakeSession(), _ auth: FakeAuthenticator = FakeAuthenticator()) -> (RemoteUnlockService, FakeLocator) {
    let locator = FakeLocator(session)
    return (RemoteUnlockService(pairing: pairing, locator: locator, authenticator: auth), locator)
}

private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<500 where !condition() { await Task.yield() }
    #expect(condition())
}

@Test func successAndCompatibility() async {
    for (response, expected) in [((true, UnlockResultCode.verified), UnlockOutcome.verified), ((true, nil), .sentUnverified), ((false, .invalidSignature), .invalidPairing), ((true, .unrecognized), .failed), ((true, .invalidSignature), .invalidPairing)] {
        let pairing = FakePairing(), session = FakeSession()
        session.response = response
        let (service, _) = fixture(pairing, session)
        #expect(await service.unlock(reason: "Unlock") == expected)
        #expect(session.counts.1 == 1 && session.counts.2 == 1)
        #expect(session.signature == UnlockWire.signature(challenge: testHandshake.challenge!, token: testSnapshot.token))
        #expect((try? pairing.snapshot()) == testSnapshot)
    }
}

@Test func preflightFailures() async {
    let missing = FakePairing(nil), session = FakeSession()
    let (service, _) = fixture(missing, session)
    #expect(await service.unlock(reason: "Unlock") == .notPaired)
    missing.fail()
    #expect(await service.unlock(reason: "Unlock") == .credentialUnavailable)
    #expect(session.counts.2 == 0)
    let tokenOnly = FakePairing(PairingSnapshot(token: testSnapshot.token, target: nil))
    let (other, _) = fixture(tokenOnly, session)
    #expect(await other.unlock(reason: "Unlock") == .noTargetSelected)
}

@Test func locateAndHandshakeFailures() async {
    for (error, expected) in [(UnlockLocatorError.macNotFound, UnlockOutcome.macNotFound), (.localNetworkDenied, .localNetworkDenied)] {
        let session = FakeSession(), (service, locator) = fixture(FakePairing(), session)
        locator.error = error
        #expect(await service.unlock(reason: "Unlock") == expected)
        #expect(session.counts.2 == 0)
    }
    let mismatch = FakeSession(); mismatch.handshake = UnlockHandshake(serverId: "other", challenge: Data([1]), unlockAvailable: true)
    let (service, _) = fixture(FakePairing(), mismatch)
    #expect(await service.unlock(reason: "Unlock") == .macNotFound)
    #expect(mismatch.counts.1 == 0 && mismatch.counts.2 == 1)
    let unavailable = FakeSession(); unavailable.handshake = UnlockHandshake(serverId: "mac", challenge: nil, unlockAvailable: false)
    let (another, _) = fixture(FakePairing(), unavailable)
    #expect(await another.unlock(reason: "Unlock") == .notConfiguredOnMac)
    #expect(unavailable.counts.2 == 1)
}

@Test func directOpenFailures() async {
    for (error, expected) in [(UnlockSessionError.connectionFailed, UnlockOutcome.connectionLost), (.localNetworkDenied, .localNetworkDenied)] {
        let session = FakeSession(); session.openError = error
        let (service, _) = fixture()
        #expect(await service.unlock(route: .directSession(session, displayName: "Desk"), reason: "Unlock") == expected)
        #expect(session.counts.0 == 1 && session.counts.1 == 0 && session.counts.2 == 1)
    }
}

@Test func authenticationErrors() async {
    for (error, expected) in [(AuthenticationError.cancelled, UnlockOutcome.cancelled), (.failed, .authenticationFailed), (.notInteractive, .authenticationNeedsForeground)] {
        let auth = FakeAuthenticator(); auth.error = error
        let session = FakeSession(); let (service, _) = fixture(FakePairing(), session, auth)
        #expect(await service.unlock(reason: "Unlock") == expected)
        #expect(session.counts.1 == 0 && session.counts.2 == 1)
    }
}

@Test func pairingChangesDuringAuthentication() async {
    let changed = [PairingSnapshot(token: Data([9]), target: testTarget), PairingSnapshot(token: testSnapshot.token, target: UnlockTarget(serverId: "other", displayName: "Desk", pairedAt: .now)), nil]
    for value in changed {
        let pairing = FakePairing(), session = FakeSession(), auth = FakeAuthenticator()
        let gate = Gate<Void>(); auth.gate = gate
        let (service, _) = fixture(pairing, session, auth)
        let task = Task { await service.unlock(reason: "Unlock") }
        await waitUntil { auth.counts.0 == 1 }
        pairing.set(value); gate.finish(.success(()))
        #expect(await task.value == .pairingChanged)
        #expect(session.counts.1 == 0 && session.counts.2 == 1)
    }
}

@Test func pairingReadFailureAfterAuthentication() async {
    let pairing = FakePairing(), session = FakeSession(), auth = FakeAuthenticator(); let gate = Gate<Void>(); auth.gate = gate
    let (service, _) = fixture(pairing, session, auth)
    let task = Task { await service.unlock(reason: "Unlock") }
    await waitUntil { auth.counts.0 == 1 }
    pairing.fail(); gate.finish(.success(()))
    #expect(await task.value == .credentialUnavailable)
    #expect(session.counts.1 == 0 && session.counts.2 == 1)
}

@Test func cancellationBeforeSend() async {
    let session = FakeSession(), auth = FakeAuthenticator(); let gate = Gate<Void>(); auth.gate = gate
    let (service, _) = fixture(FakePairing(), session, auth)
    let task = Task { await service.unlock(reason: "Unlock") }
    await waitUntil { auth.counts.0 == 1 }
    task.cancel()
    #expect(await task.value == .cancelled)
    #expect(auth.counts.1 == 1 && session.counts.1 == 0 && session.counts.2 == 1)
}

@Test func cancellationAtHandshakeAndRevalidation() async {
    let session = FakeSession(), auth = FakeAuthenticator()
    let (service, locator) = fixture(FakePairing(), session, auth)
    locator.cancelOnReturn = true
    let first = Task { await service.unlock(reason: "Unlock") }
    #expect(await first.value == .cancelled)
    #expect(auth.counts.0 == 0 && session.counts.1 == 0 && session.counts.2 == 1)

    let pairing = FakePairing(), secondSession = FakeSession(), secondAuth = FakeAuthenticator()
    pairing.cancelOnSecondRead = true
    let (second, _) = fixture(pairing, secondSession, secondAuth)
    let afterAuth = Task { await second.unlock(reason: "Unlock") }
    #expect(await afterAuth.value == .cancelled)
    #expect(secondAuth.counts.0 == 1 && secondSession.counts.1 == 0 && secondSession.counts.2 == 1)
}

@Test func cancellationDuringLocateAndOpen() async {
    let (service, locator) = fixture()
    let locateGate = Gate<(UnlockSession, UnlockHandshake)>(); locator.gate = locateGate
    let locateTask = Task { await service.unlock(reason: "Unlock") }
    await Task.yield(); locateTask.cancel()
    locateGate.finish(.failure(CancellationError()))
    #expect(await locateTask.value == .cancelled)
    let openSession = FakeSession(), openGate = Gate<UnlockHandshake>(); openSession.openGate = openGate
    let openTask = Task { await service.unlock(route: .directSession(openSession, displayName: "Desk"), reason: "Unlock") }
    await waitUntil { openSession.counts.0 == 1 }
    openTask.cancel(); openGate.finish(.failure(CancellationError()))
    #expect(await openTask.value == .cancelled)
    #expect(openSession.counts.2 == 1)
}

@Test func uncertainSendNeverRetries() async {
    for error in [UnlockSessionError.timedOut, .closed, .cancelled] {
        let session = FakeSession(); session.sendError = error
        let (service, _) = fixture(FakePairing(), session)
        #expect(await service.unlock(reason: "Unlock") == .resultUnknown)
        #expect(session.counts.1 == 1 && session.counts.2 == 1)
    }
    let session = FakeSession(), gate = Gate<(Bool, UnlockResultCode?)>(); session.sendGate = gate
    let (service, _) = fixture(FakePairing(), session)
    let task = Task { await service.unlock(reason: "Unlock") }
    await waitUntil { session.counts.1 == 1 }
    task.cancel(); gate.finish(.failure(UnlockSessionError.cancelled))
    #expect(await task.value == .resultUnknown)
    #expect(session.counts.1 == 1 && session.counts.2 == 1)
}

@Test func reentrancyAcrossRoutes() async {
    let session = FakeSession(), auth = FakeAuthenticator(), gate = Gate<Void>(); auth.gate = gate
    let (service, _) = fixture(FakePairing(), session, auth)
    let first = Task { await service.unlock(route: .directSession(session, displayName: "Desk"), reason: "UI") }
    await waitUntil { auth.counts.0 == 1 }
    #expect(await service.unlock(reason: "Intent") == .busy)
    #expect(session.counts.1 == 0)
    gate.finish(.success(()))
    #expect(await first.value == .verified)
    auth.gate = nil
    #expect(await service.unlock(reason: "Intent") == .verified)
    #expect(auth.counts.0 == 2 && session.counts.1 == 2 && session.counts.2 == 2)
}

@Test func concurrentBoundRequests() async {
    let session = FakeSession(), auth = FakeAuthenticator(), gate = Gate<Void>(); auth.gate = gate
    let (service, _) = fixture(FakePairing(), session, auth)
    let first = Task { await service.unlock(reason: "First") }
    await waitUntil { auth.counts.0 == 1 }
    #expect(await service.unlock(reason: "Second") == .busy)
    gate.finish(.success(()))
    #expect(await first.value == .verified)
    #expect(session.counts.1 == 1 && session.counts.2 == 1)
}
