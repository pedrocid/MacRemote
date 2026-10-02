import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum SessionLockState: Equatable, Sendable {
    case locked
    case unlocked
    case unknown
}

protocol SessionLockStateProviding: Sendable {
    func currentState() -> SessionLockState
}

extension SessionLockState {
    static func from(sessionDictionary: [String: Any]?) -> SessionLockState {
        // These CGSession keys are undocumented and NEED DEVICE VERIFICATION on macOS 27.
        guard let sessionDictionary,
              isTruthy(sessionDictionary["kCGSSessionOnConsoleKey"]) else {
            return .unknown
        }

        return isTruthy(sessionDictionary["CGSSessionScreenIsLocked"]) ? .locked : .unlocked
    }

    private static func isTruthy(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return number != 0
    }
}

#if canImport(CoreGraphics)
struct CGSessionLockStateProvider: SessionLockStateProviding {
    func currentState() -> SessionLockState {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        return .from(sessionDictionary: dictionary)
    }
}
#endif
