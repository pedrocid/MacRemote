import Foundation
import CryptoKit

enum UnlockResultCode: String, Codable, Sendable {
    case verified, alreadyUnlocked, inProgress, lockStateUnknown, invalidSignature
    case notConfigured, inputNotPermitted, postFailed, notVerified, unrecognized

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try? container.decode(String.self)
        self = value.flatMap(Self.init(rawValue:)) ?? .unrecognized
    }

    var isSuccess: Bool { self == .verified || self == .alreadyUnlocked }
}

enum UnlockWire {
    static let signatureContext = Data("unlock".utf8)
    static let verifyDeadline: TimeInterval = 6
    static let verifyPollInterval: TimeInterval = 0.25
    static let clientAckTimeout: TimeInterval = 12
    static let maxFrameBytes = 262_144

    static func signature(challenge: Data, token: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: challenge + signatureContext,
            using: SymmetricKey(data: token)
        ))
    }
}
