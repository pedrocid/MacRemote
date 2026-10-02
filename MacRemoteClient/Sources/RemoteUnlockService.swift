import Foundation
import CryptoKit

protocol DeviceOwnerAuthenticating: Sendable {
    func authenticate(reason: String) async throws
    func cancel()
}

enum AuthenticationError: Error, Equatable {
    case cancelled, failed, notInteractive
}

protocol PairingSnapshotProviding: Sendable {
    func snapshot() throws -> PairingSnapshot?
}

extension UnlockPairingStore: PairingSnapshotProviding {}

protocol UnlockSessionLocating: Sendable {
    func locate(target: UnlockTarget) async throws -> (UnlockSession, UnlockHandshake)
}

extension UnlockMacLocator: UnlockSessionLocating {}

enum UnlockRoute: Sendable {
    case boundTarget
    case directSession(UnlockSession, displayName: String)
}

actor RemoteUnlockService {
    static let shared = RemoteUnlockService()

    private var pairing: PairingSnapshotProviding?
    private var locator: UnlockSessionLocating?
    private var authenticator: DeviceOwnerAuthenticating?
    private var isRunning = false

    private init() {}

    init(pairing: PairingSnapshotProviding, locator: UnlockSessionLocating, authenticator: DeviceOwnerAuthenticating) {
        self.pairing = pairing
        self.locator = locator
        self.authenticator = authenticator
    }

    func configure(pairing: PairingSnapshotProviding, locator: UnlockSessionLocating, authenticator: DeviceOwnerAuthenticating) {
        guard self.pairing == nil else { return }
        self.pairing = pairing
        self.locator = locator
        self.authenticator = authenticator
    }

    func unlock(route: UnlockRoute = .boundTarget, reason: String, requireAuthentication: Bool = true) async -> UnlockOutcome {
        guard !isRunning else { return .busy }
        isRunning = true
        defer { isRunning = false }

        guard let pairing, let locator, let authenticator else { return .failed }
        if Task.isCancelled { return .cancelled }
        let snapshot: PairingSnapshot
        do {
            guard let value = try pairing.snapshot() else { return .notPaired }
            snapshot = value
        } catch { return Task.isCancelled ? .cancelled : .credentialUnavailable }

        let session: UnlockSession
        let handshake: UnlockHandshake
        switch route {
        case .boundTarget:
            guard let target = snapshot.target else { return .noTargetSelected }
            do {
                (session, handshake) = try await locator.locate(target: target)
            } catch {
                if Task.isCancelled || error is CancellationError { return .cancelled }
                return error as? UnlockLocatorError == .localNetworkDenied ? .localNetworkDenied : .macNotFound
            }
            defer { session.close() }
            if Task.isCancelled { return .cancelled }
            guard handshake.serverId == target.serverId else { return .macNotFound }
            return await finish(session: session, handshake: handshake, snapshot: snapshot, route: route, pairing: pairing, authenticator: authenticator, reason: reason, requireAuthentication: requireAuthentication)

        case .directSession(let direct, _):
            session = direct
            defer { session.close() }
            do {
                handshake = try await session.open(timeout: 5)
            } catch {
                if Task.isCancelled || error is CancellationError { return .cancelled }
                return error as? UnlockSessionError == .localNetworkDenied ? .localNetworkDenied : .connectionLost
            }
            if Task.isCancelled { return .cancelled }
            return await finish(session: session, handshake: handshake, snapshot: snapshot, route: route, pairing: pairing, authenticator: authenticator, reason: reason, requireAuthentication: requireAuthentication)
        }
    }

    private func finish(session: UnlockSession, handshake: UnlockHandshake, snapshot: PairingSnapshot, route: UnlockRoute, pairing: PairingSnapshotProviding, authenticator: DeviceOwnerAuthenticating, reason: String, requireAuthentication: Bool) async -> UnlockOutcome {
        guard handshake.unlockAvailable, let challenge = handshake.challenge else { return .notConfiguredOnMac }
        if Task.isCancelled { return .cancelled }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                // Skipped only when the user turned off the extra Face ID check for Shortcuts (the intent's
                // device-authentication policy still requires an unlocked iPhone).
                if requireAuthentication { try await authenticator.authenticate(reason: reason) }
            } onCancel: {
                authenticator.cancel()
            }
        } catch {
            if Task.isCancelled || error is CancellationError || error as? AuthenticationError == .cancelled { return .cancelled }
            if error as? AuthenticationError == .notInteractive { return .authenticationNeedsForeground }
            return .authenticationFailed
        }
        if Task.isCancelled { return .cancelled }

        let current: PairingSnapshot
        do {
            guard let value = try pairing.snapshot() else { return .pairingChanged }
            current = value
        } catch { return Task.isCancelled ? .cancelled : .credentialUnavailable }
        guard current.token == snapshot.token else { return .pairingChanged }
        if case .boundTarget = route {
            guard current.target?.serverId == snapshot.target?.serverId else { return .pairingChanged }
        }
        if Task.isCancelled { return .cancelled }

        let signature = UnlockWire.signature(challenge: challenge, token: snapshot.token)
        do {
            let result = try await session.sendUnlock(signature: signature, timeout: UnlockWire.clientAckTimeout)
            return UnlockOutcome.fromServer(success: result.success, code: result.code)
        } catch {
            return .resultUnknown
        }
    }
}
