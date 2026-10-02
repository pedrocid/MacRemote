import Foundation
import CryptoKit

struct UnlockSecrets: Sendable {
    let token: Data
    let password: String
}

@MainActor
final class UnlockVerifier<ConnectionID: Hashable & Sendable> {
    private(set) var isInProgress = false
    private var challenges: [ConnectionID: Data] = [:]
    private var liveConnections: Set<ConnectionID> = []

    private let loadSecrets: () throws -> UnlockSecrets?
    private let inputPermitted: () -> Bool
    private let lockState: SessionLockStateProviding
    private let typePassword: (String) async -> UnlockTypingResult
    private let randomChallenge: () -> Data
    private let sleep: (TimeInterval) async -> Void
    private let now: () -> Date
    private let verifyDeadline: TimeInterval
    private let pollInterval: TimeInterval

    init(
        loadSecrets: @escaping () throws -> UnlockSecrets?,
        inputPermitted: @escaping () -> Bool,
        lockState: SessionLockStateProviding,
        typePassword: @escaping (String) async -> UnlockTypingResult,
        randomChallenge: @escaping () -> Data,
        sleep: @escaping (TimeInterval) async -> Void,
        now: @escaping () -> Date,
        verifyDeadline: TimeInterval = UnlockWire.verifyDeadline,
        pollInterval: TimeInterval = UnlockWire.verifyPollInterval
    ) {
        self.loadSecrets = loadSecrets
        self.inputPermitted = inputPermitted
        self.lockState = lockState
        self.typePassword = typePassword
        self.randomChallenge = randomChallenge
        self.sleep = sleep
        self.now = now
        self.verifyDeadline = verifyDeadline
        self.pollInterval = pollInterval
    }

    func issueChallenge(for id: ConnectionID) -> Data {
        liveConnections.insert(id)
        let challenge = randomChallenge()
        challenges[id] = challenge
        return challenge
    }

    func removeConnection(_ id: ConnectionID) {
        liveConnections.remove(id)
        challenges.removeValue(forKey: id)
    }

    func handleUnlock(signature: Data, from id: ConnectionID) async -> (code: UnlockResultCode, nextChallenge: Data?) {
        guard !isInProgress else { return (.inProgress, nil) }
        isInProgress = true
        defer { isInProgress = false }

        let code: UnlockResultCode
        if let challenge = challenges.removeValue(forKey: id) {
            if let secrets = try? loadSecrets() {
                let expected = UnlockWire.signature(challenge: challenge, token: secrets.token)
                if signature.constantTimeEquals(expected) {
                    if inputPermitted() {
                        switch lockState.currentState() {
                        case .unlocked: code = .alreadyUnlocked
                        case .unknown: code = .lockStateUnknown
                        case .locked:
                            switch await typePassword(secrets.password) {
                            case .skippedAlreadyUnlocked: code = .alreadyUnlocked
                            case .skippedLockStateUnknown: code = .lockStateUnknown
                            case .postFailed: code = .postFailed
                            case .typed:
                                let deadline = now().addingTimeInterval(verifyDeadline)
                                while true {
                                    if lockState.currentState() == .unlocked {
                                        code = .verified
                                        break
                                    }
                                    if now() >= deadline {
                                        code = .notVerified
                                        break
                                    }
                                    await sleep(pollInterval)
                                }
                            }
                        }
                    } else {
                        code = .inputNotPermitted
                    }
                } else {
                    code = .invalidSignature
                }
            } else {
                code = .notConfigured
            }
        } else {
            code = .invalidSignature
        }

        guard liveConnections.contains(id) else { return (code, nil) }
        let nextChallenge = randomChallenge()
        challenges[id] = nextChallenge
        return (code, nextChallenge)
    }
}

extension Data {
    func constantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).reduce(UInt8(0)) { result, pair in
            result | (pair.0 ^ pair.1)
        } == 0
    }
}
