import Foundation
import CryptoKit
import Testing
@testable import ClientUnlockLogic

private enum OldServerMessage: Codable {
    case connected(screenWidth: Double, screenHeight: Double, unlockChallenge: Data?, unlockAvailable: Bool)
    case unlockResult(success: Bool, message: String)
}

private func decode(_ json: String) throws -> ServerMessage {
    try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))
}

@Test func oldConnectedDecodes() throws {
    let message = try decode(#"{"connected":{"screenWidth":1,"screenHeight":2,"unlockAvailable":true}}"#)
    guard case .connected(1, 2, nil, true, nil) = message else {
        Issue.record("Old connected payload did not decode with nil optionals")
        return
    }
}

@Test func oldResultAndNullCodeDecode() throws {
    for json in [
        #"{"unlockResult":{"success":true,"message":"Unlock command sent to the Mac."}}"#,
        #"{"unlockResult":{"success":true,"message":"Unlock command sent to the Mac.","code":null}}"#,
    ] {
        guard case .unlockResult(true, "Unlock command sent to the Mac.", nil) = try decode(json) else {
            Issue.record("Old or null result did not decode")
            return
        }
    }
}

@Test func unknownCodesAndContradictoryResultDecode() throws {
    for code in [#""somethingNew""#, "42"] {
        let json = #"{"unlockResult":{"success":false,"message":"failed","code":\#(code)}}"#
        guard case .unlockResult(false, "failed", .some(.unrecognized)) = try decode(json) else {
            Issue.record("Unknown result code did not become unrecognized")
            return
        }
    }
    guard case .unlockResult(true, "failed", .some(.invalidSignature)) = try decode(
        #"{"unlockResult":{"success":true,"message":"failed","code":"invalidSignature"}}"#
    ) else {
        Issue.record("Contradictory result was changed during decoding")
        return
    }
    #expect(!UnlockResultCode.invalidSignature.isSuccess)
    #expect(UnlockResultCode.verified.isSuccess)
    #expect(UnlockResultCode.alreadyUnlocked.isSuccess)
}

@Test func newCasesDecodeWithOldSchemaAndRoundTrip() throws {
    let messages: [ServerMessage] = [
        .connected(screenWidth: 1, screenHeight: 2, unlockChallenge: Data([1, 2]), unlockAvailable: true, serverId: "test-mac"),
        .unlockResult(success: true, message: "verified", code: .verified),
    ]
    for message in messages {
        let encoded = try JSONEncoder().encode(message)
        _ = try JSONDecoder().decode(OldServerMessage.self, from: encoded)
        let roundTrip = try JSONDecoder().decode(ServerMessage.self, from: encoded)
        switch (message, roundTrip) {
        case let (.connected(w, h, challenge, available, id), .connected(w2, h2, challenge2, available2, id2)):
            #expect(w == w2 && h == h2 && challenge == challenge2 && available == available2 && id == id2)
        case let (.unlockResult(success, text, code), .unlockResult(success2, text2, code2)):
            #expect(success == success2 && text == text2 && code == code2)
        default:
            Issue.record("New message round trip changed case")
        }
    }
}

@Test func signatureMatchesManualHMAC() {
    let challenge = Data([3, 4, 5])
    let token = Data(repeating: 1, count: 32)
    let manual = Data(HMAC<SHA256>.authenticationCode(
        for: challenge + Data("unlock".utf8),
        using: SymmetricKey(data: token)
    ))
    #expect(UnlockWire.signature(challenge: challenge, token: token) == manual)
}
