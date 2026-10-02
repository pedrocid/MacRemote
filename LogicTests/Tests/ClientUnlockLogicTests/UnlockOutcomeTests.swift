import Foundation
import Testing
@testable import ClientUnlockLogic

@Test func serverResultCodesMapToOutcomes() {
    let cases: [(UnlockResultCode, UnlockOutcome)] = [
        (.verified, .verified),
        (.alreadyUnlocked, .alreadyUnlocked),
        (.inProgress, .inProgress),
        (.lockStateUnknown, .lockStateUnknown),
        (.invalidSignature, .invalidPairing),
        (.notConfigured, .notConfiguredOnMac),
        (.inputNotPermitted, .inputNotPermittedOnMac),
        (.postFailed, .postFailed),
        (.notVerified, .notVerified),
        (.unrecognized, .failed),
    ]

    for (code, expected) in cases {
        #expect(UnlockOutcome.fromServer(success: false, code: code) == expected)
        #expect(UnlockOutcome.fromServer(success: true, code: code) == expected)
    }
}

@Test func legacyAndContradictoryServerResultsMapSafely() {
    let legacySuccess = UnlockOutcome.fromServer(success: true, code: nil)
    #expect(legacySuccess == .sentUnverified)
    #expect(!legacySuccess.isSuccess)
    #expect(UnlockOutcome.fromServer(success: false, code: nil) == .failed)
    #expect(UnlockOutcome.fromServer(success: true, code: .invalidSignature) == .invalidPairing)
    #expect(UnlockOutcome.fromServer(success: false, code: .verified) == .verified)
    #expect(UnlockOutcome.fromServer(success: true, code: .unrecognized) == .failed)
}

@Test func futureResultCodeDecodesAsUnrecognizedAndFails() throws {
    let data = Data(#"{"unlockResult":{"success":true,"message":"x","code":"future"}}"#.utf8)
    let message = try JSONDecoder().decode(ServerMessage.self, from: data)
    guard case let .unlockResult(success, _, code) = message else {
        Issue.record("Expected unlockResult")
        return
    }
    #expect(UnlockOutcome.fromServer(success: success, code: code) == .failed)
}

@Test func everyOutcomeHasAUniqueSnakeCaseLocalizationKey() {
    #expect(UnlockOutcome.allCases.count == 23)
    let keys = UnlockOutcome.allCases.map(\.localizationKey)
    #expect(Set(keys).count == keys.count)
    for outcome in UnlockOutcome.allCases {
        #expect(!outcome.localizationKey.isEmpty)
        #expect(outcome.localizationKey == "unlock_outcome_" + snakeCase(outcome.rawValue))
    }
}

private func snakeCase(_ value: String) -> String {
    value.reduce(into: "") { result, character in
        if character.isUppercase {
            result.append("_")
            result.append(character.lowercased())
        } else {
            result.append(character)
        }
    }
}
