import Foundation
import Testing
@testable import ServerUnlockLogic

@Test func firstInitPersistsValidUUID() {
    let defaults = UserDefaults(suiteName: "test-\(UUID())")!

    let identity = ServerIdentity(defaults: defaults)

    #expect(UUID(uuidString: identity.id) != nil)
    #expect(defaults.string(forKey: ServerIdentity.defaultsKey) == identity.id)
}

@Test func secondInitReturnsSameID() {
    let defaults = UserDefaults(suiteName: "test-\(UUID())")!

    let first = ServerIdentity(defaults: defaults)
    let second = ServerIdentity(defaults: defaults)

    #expect(second.id == first.id)
}

@Test func garbageValueIsReplacedWithValidUUID() {
    let defaults = UserDefaults(suiteName: "test-\(UUID())")!
    defaults.set("not-a-uuid", forKey: ServerIdentity.defaultsKey)

    let identity = ServerIdentity(defaults: defaults)

    #expect(UUID(uuidString: identity.id) != nil)
    #expect(defaults.string(forKey: ServerIdentity.defaultsKey) == identity.id)
}
