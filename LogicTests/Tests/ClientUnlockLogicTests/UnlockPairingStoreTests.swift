import Foundation
import Testing
@testable import ClientUnlockLogic

private enum FakeError: Error { case failed }

private final class FakeTokens: UnlockTokenStoring {
    var token: Data?
    var failRead = false
    var failSave = false
    var failDelete = false

    func readToken() throws -> Data? {
        if failRead { throw FakeError.failed }
        return token
    }
    func saveToken(_ data: Data) throws {
        if failSave { throw FakeError.failed }
        token = data
    }
    func deleteToken() throws {
        if failDelete { throw FakeError.failed }
        token = nil
    }
}

private func fixture() -> (UnlockPairingStore, FakeTokens, UserDefaults) {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let tokens = FakeTokens()
    return (UnlockPairingStore(tokens: tokens, defaults: defaults), tokens, defaults)
}

@Test func emptyAndStaleTarget() throws {
    let (store, tokens, defaults) = fixture()
    #expect(store.state() == .unpaired)
    #expect(try store.snapshot() == nil)
    let target = UnlockTarget(serverId: "mac", displayName: "Mac", pairedAt: Date(timeIntervalSince1970: 1))
    defaults.set(try JSONEncoder().encode(target), forKey: UnlockPairingStore.targetKey)
    #expect(tokens.token == nil)
    #expect(try store.snapshot() == nil)
    #expect(store.state() == .unpaired)
}

@Test func pairingTransitionsAndDefaultsContainOnlyTarget() throws {
    let (store, tokens, defaults) = fixture()
    let token = Data(repeating: 0xAB, count: 32)
    let now = Date(timeIntervalSince1970: 123)
    try store.pair(token: token, serverId: "mac-1", displayName: "Desk", now: now)
    let first = UnlockTarget(serverId: "mac-1", displayName: "Desk", pairedAt: now)
    #expect(store.state() == .paired(first))
    #expect(try store.snapshot() == PairingSnapshot(token: token, target: first))

    let json = try #require(defaults.data(forKey: UnlockPairingStore.targetKey))
    let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
    #expect(Set(object.keys) == ["serverId", "displayName", "pairedAt"])
    let stored = String(describing: defaults.dictionaryRepresentation())
    #expect(!stored.contains(token.map { String(format: "%02x", $0) }.joined()))
    #expect(!stored.contains(token.map { String(format: "%02X", $0) }.joined()))
    #expect(!stored.contains(token.base64EncodedString()))

    try store.pair(token: token, serverId: "mac-2", displayName: "Other", now: now)
    #expect(store.target()?.serverId == "mac-2")
    try store.pair(token: token, serverId: nil, displayName: "Legacy", now: now)
    #expect(store.state() == .tokenOnlyLegacy)
    #expect(store.target() == nil)
    #expect(try store.snapshot() == PairingSnapshot(token: token, target: nil))
    #expect(defaults.object(forKey: UnlockPairingStore.targetKey) == nil)
    #expect(tokens.token == token)
}

@Test func pairWithoutServerIdAndUnpair() throws {
    let (store, tokens, _) = fixture()
    let token = Data([1, 2, 3])
    try store.pair(token: token, serverId: nil, displayName: "Legacy")
    #expect(store.state() == .tokenOnlyLegacy)
    try store.unpair()
    #expect(tokens.token == nil)
    #expect(store.state() == .unpaired)
    #expect(try store.snapshot() == nil)
}

@Test func failedSavePreservesPreviousPair() throws {
    let (store, tokens, _) = fixture()
    let original = Data([1])
    try store.pair(token: original, serverId: "old", displayName: "Old")
    let before = try store.snapshot()
    tokens.failSave = true
    #expect(throws: FakeError.self) {
        try store.pair(token: Data([2]), serverId: "new", displayName: "New")
    }
    #expect(try store.snapshot() == before)
}

@Test func failedDeleteRemovesBinding() throws {
    let (store, tokens, _) = fixture()
    try store.pair(token: Data([1]), serverId: "old", displayName: "Old")
    tokens.failDelete = true
    #expect(throws: FakeError.self) { try store.unpair() }
    #expect(store.target() == nil)
    #expect(store.state() == .tokenOnlyLegacy)
}

@Test func corruptTargetAndReadFailure() throws {
    let (store, tokens, defaults) = fixture()
    tokens.token = Data([1])
    defaults.set(Data("broken".utf8), forKey: UnlockPairingStore.targetKey)
    #expect(store.target() == nil)
    #expect(defaults.object(forKey: UnlockPairingStore.targetKey) == nil)
    #expect(store.state() == .tokenOnlyLegacy)
    tokens.failRead = true
    #expect(throws: FakeError.self) { try store.snapshot() }
    #expect(store.state() == .unpaired)
    let target = UnlockTarget(serverId: "mac", displayName: "Mac", pairedAt: Date())
    defaults.set(try JSONEncoder().encode(target), forKey: UnlockPairingStore.targetKey)
    #expect(store.state() == .paired(target))
}

@Test func pairingKeyParsing() throws {
    #expect(try UnlockCredentialStore.parsePairingKey(String(repeating: "ab", count: 32)) == Data(repeating: 0xAB, count: 32))
    #expect(throws: UnlockCredentialError.invalidKeyFormat) {
        try UnlockCredentialStore.parsePairingKey("invalid")
    }
}
