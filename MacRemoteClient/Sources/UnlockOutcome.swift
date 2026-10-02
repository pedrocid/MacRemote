import Foundation

enum UnlockOutcome: String, CaseIterable, Equatable, Sendable {
    case verified
    case alreadyUnlocked
    /// The legacy server acknowledged the command without verifying the lock state.
    case sentUnverified
    case notVerified
    /// The unlock send was started, then timed out, disconnected, was cancelled, or failed.
    case resultUnknown
    case inProgress
    case lockStateUnknown
    case invalidPairing
    case notConfiguredOnMac
    case inputNotPermittedOnMac
    case postFailed
    case failed
    case cancelled
    case authenticationFailed
    case authenticationNeedsForeground
    case macNotFound
    case localNetworkDenied
    case notPaired
    case noTargetSelected
    /// The pairing changed during authentication, so nothing was sent.
    case pairingChanged
    /// Reading the Keychain credential failed.
    case credentialUnavailable
    case busy
    /// The connection failed before any unlock send began.
    case connectionLost

    static func fromServer(success: Bool, code: UnlockResultCode?) -> UnlockOutcome {
        guard let code else { return success ? .sentUnverified : .failed }
        switch code {
        case .verified: return .verified
        case .alreadyUnlocked: return .alreadyUnlocked
        case .inProgress: return .inProgress
        case .lockStateUnknown: return .lockStateUnknown
        case .invalidSignature: return .invalidPairing
        case .notConfigured: return .notConfiguredOnMac
        case .inputNotPermitted: return .inputNotPermittedOnMac
        case .postFailed: return .postFailed
        case .notVerified: return .notVerified
        case .unrecognized: return .failed
        }
    }

    var isSuccess: Bool {
        self == .verified || self == .alreadyUnlocked
    }

    var localizationKey: String {
        switch self {
        case .verified: return "unlock_outcome_verified"
        case .alreadyUnlocked: return "unlock_outcome_already_unlocked"
        case .sentUnverified: return "unlock_outcome_sent_unverified"
        case .notVerified: return "unlock_outcome_not_verified"
        case .resultUnknown: return "unlock_outcome_result_unknown"
        case .inProgress: return "unlock_outcome_in_progress"
        case .lockStateUnknown: return "unlock_outcome_lock_state_unknown"
        case .invalidPairing: return "unlock_outcome_invalid_pairing"
        case .notConfiguredOnMac: return "unlock_outcome_not_configured_on_mac"
        case .inputNotPermittedOnMac: return "unlock_outcome_input_not_permitted_on_mac"
        case .postFailed: return "unlock_outcome_post_failed"
        case .failed: return "unlock_outcome_failed"
        case .cancelled: return "unlock_outcome_cancelled"
        case .authenticationFailed: return "unlock_outcome_authentication_failed"
        case .authenticationNeedsForeground: return "unlock_outcome_authentication_needs_foreground"
        case .macNotFound: return "unlock_outcome_mac_not_found"
        case .localNetworkDenied: return "unlock_outcome_local_network_denied"
        case .notPaired: return "unlock_outcome_not_paired"
        case .noTargetSelected: return "unlock_outcome_no_target_selected"
        case .pairingChanged: return "unlock_outcome_pairing_changed"
        case .credentialUnavailable: return "unlock_outcome_credential_unavailable"
        case .busy: return "unlock_outcome_busy"
        case .connectionLost: return "unlock_outcome_connection_lost"
        }
    }
}
