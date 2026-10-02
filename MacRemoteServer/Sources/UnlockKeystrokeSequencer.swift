import Foundation

enum UnlockTypingResult: Equatable, Sendable {
    case typed
    case skippedAlreadyUnlocked
    case skippedLockStateUnknown
    case postFailed
}

struct UnlockKeystrokeSequencer {
    let lockState: () -> SessionLockState
    let postWake: () -> Bool
    let postPassword: (String) -> Bool
    let sleep: (TimeInterval) -> Void
    var wakeDelay: TimeInterval = 0.7

    func run(password: String) -> UnlockTypingResult {
        guard !password.isEmpty else { return .postFailed }

        switch lockState() {
        case .locked: break
        case .unlocked: return .skippedAlreadyUnlocked
        case .unknown: return .skippedLockStateUnknown
        }

        guard postWake() else { return .postFailed }
        sleep(wakeDelay)

        switch lockState() {
        case .locked: break
        case .unlocked: return .skippedAlreadyUnlocked
        case .unknown: return .skippedLockStateUnknown
        }

        return postPassword(password) ? .typed : .postFailed
    }
}
