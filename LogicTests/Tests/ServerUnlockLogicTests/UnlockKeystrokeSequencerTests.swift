import Foundation
import Testing
@testable import ServerUnlockLogic

private final class TypingRecorder {
    var events: [String] = []
    var states: [SessionLockState]
    var wakeSucceeds = true
    var passwordSucceeds = true

    init(_ states: [SessionLockState]) { self.states = states }

    func run(_ password: String = "secret") -> UnlockTypingResult {
        let sequencer = UnlockKeystrokeSequencer(
            lockState: {
                self.events.append("lockCheck")
                return self.states.removeFirst()
            },
            postWake: {
                self.events.append("wake")
                return self.wakeSucceeds
            },
            postPassword: { value in
                self.events.append("password")
                return value == password && self.passwordSucceeds
            },
            sleep: { _ in self.events.append("sleep") }
        )
        return sequencer.run(password: password)
    }
}

@Test func typingSequenceWhenLocked() {
    let recorder = TypingRecorder([.locked, .locked])
    #expect(recorder.run() == .typed)
    #expect(recorder.events == ["lockCheck", "wake", "sleep", "lockCheck", "password"])
}

@Test func typingSequenceStopsBeforeWakeIfUnlocked() {
    let recorder = TypingRecorder([.unlocked])
    #expect(recorder.run() == .skippedAlreadyUnlocked)
    #expect(recorder.events == ["lockCheck"])
}

@Test func typingSequenceStopsBeforeWakeIfUnknown() {
    let recorder = TypingRecorder([.unknown])
    #expect(recorder.run() == .skippedLockStateUnknown)
    #expect(recorder.events == ["lockCheck"])
}

@Test func typingSequenceStopsAfterWakeIfUnlocked() {
    let recorder = TypingRecorder([.locked, .unlocked])
    #expect(recorder.run() == .skippedAlreadyUnlocked)
    #expect(recorder.events == ["lockCheck", "wake", "sleep", "lockCheck"])
}

@Test func typingSequenceStopsAfterWakeIfUnknown() {
    let recorder = TypingRecorder([.locked, .unknown])
    #expect(recorder.run() == .skippedLockStateUnknown)
    #expect(recorder.events == ["lockCheck", "wake", "sleep", "lockCheck"])
}

@Test func typingSequenceStopsWhenWakeFails() {
    let recorder = TypingRecorder([.locked])
    recorder.wakeSucceeds = false
    #expect(recorder.run() == .postFailed)
    #expect(recorder.events == ["lockCheck", "wake"])
}

@Test func typingSequenceReportsPasswordPostFailure() {
    let recorder = TypingRecorder([.locked, .locked])
    recorder.passwordSucceeds = false
    #expect(recorder.run() == .postFailed)
    #expect(recorder.events == ["lockCheck", "wake", "sleep", "lockCheck", "password"])
}

@Test func typingSequenceRejectsEmptyPasswordWithoutEvents() {
    let recorder = TypingRecorder([])
    #expect(recorder.run("") == .postFailed)
    #expect(recorder.events.isEmpty)
}
