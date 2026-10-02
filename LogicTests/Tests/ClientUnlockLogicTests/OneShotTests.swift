import Foundation
import Testing
@testable import ClientUnlockLogic

@Test func valueBeforeWaitAndDuplicateResume() async throws {
    let shot = OneShot<Int>()
    shot.resume(returning: 4)
    shot.resume(returning: 9)
    #expect(try await shot.wait(timeout: 0.1) == 4)
}

@Test func cancelBeforeRegistration() async {
    let shot = OneShot<Int>()
    let task = Task { try await shot.wait(timeout: 1) }
    task.cancel()
    do { _ = try await task.value; Issue.record("Expected cancellation") }
    catch { #expect(error as? UnlockSessionError == .cancelled) }
}

@Test func timeoutThenLateResume() async {
    let shot = OneShot<Int>()
    do { _ = try await shot.wait(timeout: 0.01); Issue.record("Expected timeout") }
    catch { #expect(error as? UnlockSessionError == .timedOut) }
    shot.resume(returning: 5)
}

@Test func concurrentResumesChooseOneValue() async throws {
    let shot = OneShot<Int>()
    await withTaskGroup(of: Void.self) { group in
        for value in 0..<100 { group.addTask { shot.resume(returning: value) } }
    }
    #expect((0..<100).contains(try await shot.wait(timeout: 1)))
}

@Test func resultTimeoutRaceHasOneOutcome() async {
    let shot = OneShot<Int>()
    let producer = Task {
        try? await Task.sleep(nanoseconds: 10_000_000)
        shot.resume(returning: 7)
    }
    do { #expect(try await shot.wait(timeout: 0.01) == 7) }
    catch { #expect(error as? UnlockSessionError == .timedOut) }
    _ = await producer.value
}
