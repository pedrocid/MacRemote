import Foundation
import Testing
@testable import ServerUnlockLogic

private final class ScriptedState: SessionLockStateProviding, @unchecked Sendable {
    var states: [SessionLockState]
    var fallback: SessionLockState
    init(_ states: [SessionLockState], fallback: SessionLockState = .locked) {
        self.states = states
        self.fallback = fallback
    }
    func currentState() -> SessionLockState {
        states.isEmpty ? fallback : states.removeFirst()
    }
}

@MainActor
private final class Fixture {
    let token = Data(repeating: 7, count: 32)
    let password = "secret"
    let state: ScriptedState
    var typerResult: UnlockTypingResult = .typed
    var typedPasswords: [String] = []
    var permitted = true
    var secretMode = 0 // 0: present, 1: nil, 2: throws
    var elapsed: TimeInterval = 0
    var challengeNumber: UInt8 = 0
    lazy var verifier = UnlockVerifier<Int>(
        loadSecrets: {
            if self.secretMode == 2 { throw FixtureError.failure }
            if self.secretMode == 1 { return nil }
            return UnlockSecrets(token: self.token, password: self.password)
        },
        inputPermitted: { self.permitted },
        lockState: state,
        typePassword: { password in
            self.typedPasswords.append(password)
            return self.typerResult
        },
        randomChallenge: {
            self.challengeNumber &+= 1
            return Data(repeating: self.challengeNumber, count: 32)
        },
        sleep: { interval in self.elapsed += interval },
        now: { Date(timeIntervalSince1970: self.elapsed) }
    )
    init(_ states: [SessionLockState] = [.locked, .unlocked], fallback: SessionLockState = .locked) {
        state = ScriptedState(states, fallback: fallback)
    }
    func signature(_ challenge: Data, token: Data? = nil) -> Data {
        UnlockWire.signature(challenge: challenge, token: token ?? self.token)
    }
}
private enum FixtureError: Error { case failure }

@Test @MainActor func verifiedAndReplay() async {
    let f = Fixture()
    let challenge = f.verifier.issueChallenge(for: 1)
    let signature = f.signature(challenge)
    let first = await f.verifier.handleUnlock(signature: signature, from: 1)
    #expect(first.code == .verified)
    #expect(first.nextChallenge != challenge)
    #expect(f.typedPasswords == ["secret"])
    let replay = await f.verifier.handleUnlock(signature: signature, from: 1)
    #expect(replay.code == .invalidSignature)
    #expect(f.typedPasswords.count == 1)
    #expect(!f.verifier.isInProgress)
}

@Test @MainActor func invalidSignaturesAndUnknownID() async {
    let f = Fixture()
    let challenge = f.verifier.issueChallenge(for: 1)
    let wrong = await f.verifier.handleUnlock(signature: f.signature(challenge, token: Data(repeating: 8, count: 32)), from: 1)
    #expect(wrong.code == .invalidSignature)
    let unknown = await f.verifier.handleUnlock(signature: f.signature(challenge), from: 999)
    #expect(unknown.code == .invalidSignature)
    #expect(unknown.nextChallenge == nil)
    #expect(f.typedPasswords.isEmpty)
    #expect(!f.verifier.isInProgress)
}

@Test @MainActor func prechecks() async {
    for (state, permitted, expected) in [
        (SessionLockState.locked, false, UnlockResultCode.inputNotPermitted),
        (.unlocked, true, .alreadyUnlocked),
        (.unknown, true, .lockStateUnknown)
    ] {
        let f = Fixture([state])
        f.permitted = permitted
        let c = f.verifier.issueChallenge(for: 1)
        let result = await f.verifier.handleUnlock(signature: f.signature(c), from: 1)
        #expect(result.code == expected)
        #expect(f.typedPasswords.isEmpty)
        #expect(!f.verifier.isInProgress)
    }
}

@Test @MainActor func typingOutcomes() async {
    for (typing, expected) in [
        (UnlockTypingResult.skippedAlreadyUnlocked, UnlockResultCode.alreadyUnlocked),
        (.skippedLockStateUnknown, .lockStateUnknown),
        (.postFailed, .postFailed)
    ] {
        let f = Fixture()
        f.typerResult = typing
        let c = f.verifier.issueChallenge(for: 1)
        let result = await f.verifier.handleUnlock(signature: f.signature(c), from: 1)
        #expect(result.code == expected)
        #expect(f.typedPasswords == ["secret"])
        #expect(!f.verifier.isInProgress)
    }
}

@Test @MainActor func deadlineAndMissingSecrets() async {
    let f = Fixture([.locked], fallback: .locked)
    let c = f.verifier.issueChallenge(for: 1)
    let result = await f.verifier.handleUnlock(signature: f.signature(c), from: 1)
    #expect(result.code == .notVerified)
    #expect(f.elapsed >= 6)
    #expect(f.typedPasswords == ["secret"])
    #expect(!f.verifier.isInProgress)
    for mode in [1, 2] {
        let missing = Fixture()
        missing.secretMode = mode
        let c = missing.verifier.issueChallenge(for: 1)
        let result = await missing.verifier.handleUnlock(signature: missing.signature(c), from: 1)
        #expect(result.code == .notConfigured)
        #expect(missing.typedPasswords.isEmpty)
        #expect(!missing.verifier.isInProgress)
    }
}

@Test @MainActor func nextChallengeIsAccepted() async {
    let f = Fixture([.unlocked, .unlocked])
    let first = f.verifier.issueChallenge(for: 1)
    let result1 = await f.verifier.handleUnlock(signature: f.signature(first), from: 1)
    #expect(result1.code == .alreadyUnlocked)
    let next = try! #require(result1.nextChallenge)
    #expect(next != first)
    let result2 = await f.verifier.handleUnlock(signature: f.signature(next), from: 1)
    #expect(result2.code == .alreadyUnlocked)
    #expect(!f.verifier.isInProgress)
}

@MainActor
private final class Suspension {
    var continuation: CheckedContinuation<UnlockTypingResult, Never>?
    var calls = 0
    func type(_ password: String) async -> UnlockTypingResult {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning: .typed)
        continuation = nil
    }
}

@Test @MainActor func concurrencyAndDisconnect() async {
    let state = ScriptedState([.locked, .unlocked, .locked, .unlocked])
    let suspension = Suspension()
    var number: UInt8 = 0
    let token = Data(repeating: 7, count: 32)
    let verifier = UnlockVerifier<Int>(
        loadSecrets: { UnlockSecrets(token: token, password: "secret") },
        inputPermitted: { true }, lockState: state,
        typePassword: { password in await suspension.type(password) },
        randomChallenge: { number &+= 1; return Data(repeating: number, count: 32) },
        sleep: { _ in }, now: { Date() }
    )
    let c1 = verifier.issueChallenge(for: 1)
    let c2 = verifier.issueChallenge(for: 2)
    let sig1 = UnlockWire.signature(challenge: c1, token: token)
    let sig2 = UnlockWire.signature(challenge: c2, token: token)
    let first = Task { await verifier.handleUnlock(signature: sig1, from: 1) }
    while suspension.continuation == nil { await Task.yield() }
    #expect(verifier.isInProgress)
    let concurrent = await verifier.handleUnlock(signature: sig2, from: 2)
    #expect(concurrent.code == .inProgress)
    #expect(concurrent.nextChallenge == nil)
    let replay = await verifier.handleUnlock(signature: sig1, from: 1)
    #expect(replay.code == .inProgress)
    #expect(suspension.calls == 1)
    verifier.removeConnection(1)
    #expect(verifier.isInProgress)
    suspension.finish()
    let completed = await first.value
    #expect(completed.code == .verified)
    #expect(completed.nextChallenge == nil)
    #expect(!verifier.isInProgress)
    let second = Task { await verifier.handleUnlock(signature: sig2, from: 2) }
    while suspension.continuation == nil { await Task.yield() }
    #expect(suspension.calls == 2)
    suspension.finish()
    let secondResult = await second.value
    #expect(secondResult.code == .verified)
    #expect(!verifier.isInProgress)
    let removedReplay = await verifier.handleUnlock(signature: sig1, from: 1)
    #expect(removedReplay.code == .invalidSignature)
    #expect(removedReplay.nextChallenge == nil)
    #expect(!verifier.isInProgress)
}
