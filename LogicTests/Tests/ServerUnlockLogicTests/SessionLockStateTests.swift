import Foundation
import Testing
@testable import ServerUnlockLogic

@Test func nilSessionIsUnknown() {
    #expect(SessionLockState.from(sessionDictionary: nil) == .unknown)
}

@Test func booleanLockedSessionIsLocked() {
    #expect(SessionLockState.from(sessionDictionary: [
        "kCGSSessionOnConsoleKey": true,
        "CGSSessionScreenIsLocked": true,
    ]) == .locked)
}

@Test func numberLockedSessionIsLocked() {
    #expect(SessionLockState.from(sessionDictionary: [
        "kCGSSessionOnConsoleKey": NSNumber(value: 1),
        "CGSSessionScreenIsLocked": NSNumber(value: 1),
    ]) == .locked)
}

@Test func onConsoleWithoutLockKeyIsUnlocked() {
    #expect(SessionLockState.from(sessionDictionary: [
        "kCGSSessionOnConsoleKey": true,
    ]) == .unlocked)
}

@Test func onConsoleWithFalseLockIsUnlocked() {
    #expect(SessionLockState.from(sessionDictionary: [
        "kCGSSessionOnConsoleKey": true,
        "CGSSessionScreenIsLocked": false,
    ]) == .unlocked)
}

@Test func offConsoleIsUnknown() {
    #expect(SessionLockState.from(sessionDictionary: [
        "kCGSSessionOnConsoleKey": false,
        "CGSSessionScreenIsLocked": true,
    ]) == .unknown)
}

@Test func emptySessionIsUnknown() {
    #expect(SessionLockState.from(sessionDictionary: [:]) == .unknown)
}

@Test func onConsoleLockedTakesPrecedence() {
    #expect(SessionLockState.from(sessionDictionary: [
        "kCGSSessionOnConsoleKey": true,
        "CGSSessionScreenIsLocked": true,
    ]) == .locked)
}
