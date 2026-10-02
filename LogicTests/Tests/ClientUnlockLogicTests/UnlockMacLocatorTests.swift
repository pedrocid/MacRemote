import Foundation
import Network
import Testing
@testable import ClientUnlockLogic

private struct FakeBrowser: UnlockServiceBrowsing {
    let candidates: [UnlockCandidate]
    var error: UnlockLocatorError?
    func browse(maxDuration: TimeInterval, preferredName: String) async throws -> [UnlockCandidate] {
        if let error { throw error }
        return candidates
    }
}

private final class FakeSession: UnlockSession, @unchecked Sendable {
    let endpointName: String?
    let identity: String?
    let openError: UnlockSessionError?
    let advanceClock: (() -> Void)?
    private let lock = NSLock()
    private var closes = 0
    private var sends = 0
    init(_ identity: String?, name: String? = nil, error: UnlockSessionError? = nil, advanceClock: (() -> Void)? = nil) {
        self.identity = identity; endpointName = name; openError = error; self.advanceClock = advanceClock
    }
    var closeCount: Int { lock.withLock { closes } }
    var sendCount: Int { lock.withLock { sends } }
    func open(timeout: TimeInterval) async throws -> UnlockHandshake {
        advanceClock?()
        if let openError { throw openError }
        return UnlockHandshake(serverId: identity, challenge: Data([1]), unlockAvailable: true)
    }
    func sendUnlock(signature: Data, timeout: TimeInterval) async throws -> (success: Bool, code: UnlockResultCode?) {
        lock.withLock { sends += 1 }
        return (true, .verified)
    }
    func close() { lock.withLock { closes += 1 } }
}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: seconds) } }
    func advance(_ amount: TimeInterval) { lock.withLock { seconds += amount } }
}

private func candidate(_ name: String) -> UnlockCandidate {
    UnlockCandidate(name: name, endpoint: .hostPort(host: .name(name, nil), port: 5150))
}

private let target = UnlockTarget(serverId: "wanted", displayName: "Desk", pairedAt: Date())

@Test func locatorFindsSingleMatch() async throws {
    let session = FakeSession("wanted")
    let locator = UnlockMacLocator(browser: FakeBrowser(candidates: [candidate("Desk")]), makeSession: { _ in session })
    let found = try await locator.locate(target: target)
    #expect(found.1.serverId == "wanted")
    #expect(session.closeCount == 0)
    #expect(session.sendCount == 0)
}

@Test func locatorFindsSecondAndClosesFirst() async throws {
    let first = FakeSession("other")
    let second = FakeSession("wanted")
    let locator = UnlockMacLocator(browser: FakeBrowser(candidates: [candidate("Desk"), candidate("Else")]), makeSession: { $0.name == "Desk" ? first : second })
    _ = try await locator.locate(target: target)
    #expect(first.closeCount == 1)
    #expect(second.closeCount == 0)
    #expect(first.sendCount == 0 && second.sendCount == 0)
}

@Test func locatorFindsRenamedMac() async throws {
    let session = FakeSession("wanted")
    let locator = UnlockMacLocator(browser: FakeBrowser(candidates: [candidate("New Name")]), makeSession: { _ in session })
    _ = try await locator.locate(target: target)
    #expect(session.sendCount == 0)
}

@Test func locatorRejectsOldServerAndEmptyResults() async {
    let old = FakeSession(nil)
    let locator = UnlockMacLocator(browser: FakeBrowser(candidates: [candidate("Desk")]), makeSession: { _ in old })
    do { _ = try await locator.locate(target: target); Issue.record("Expected missing Mac") }
    catch { #expect(error as? UnlockLocatorError == .macNotFound) }
    #expect(old.closeCount == 1 && old.sendCount == 0)
    let empty = UnlockMacLocator(browser: FakeBrowser(candidates: []), makeSession: { _ in old })
    do { _ = try await empty.locate(target: target); Issue.record("Expected missing Mac") }
    catch { #expect(error as? UnlockLocatorError == .macNotFound) }
    #expect(old.closeCount == 1)
}

@Test func locatorMapsPolicyDenial() async {
    let session = FakeSession(nil, error: .localNetworkDenied)
    let browserDenied = UnlockMacLocator(browser: FakeBrowser(candidates: [], error: .localNetworkDenied), makeSession: { _ in session })
    do { _ = try await browserDenied.locate(target: target); Issue.record("Expected denial") }
    catch { #expect(error as? UnlockLocatorError == .localNetworkDenied) }
    let openDenied = UnlockMacLocator(browser: FakeBrowser(candidates: [candidate("Desk")]), makeSession: { _ in session })
    do { _ = try await openDenied.locate(target: target); Issue.record("Expected denial") }
    catch { #expect(error as? UnlockLocatorError == .localNetworkDenied) }
    #expect(session.closeCount == 1 && session.sendCount == 0)
}

@Test func locatorStopsAtOverallDeadline() async {
    let clock = FakeClock()
    let first = FakeSession(nil, error: .timedOut, advanceClock: { clock.advance(8) })
    let second = FakeSession("wanted")
    let locator = UnlockMacLocator(browser: FakeBrowser(candidates: [candidate("Desk"), candidate("Other")]), makeSession: { $0.name == "Desk" ? first : second }, now: { clock.now() })
    do { _ = try await locator.locate(target: target); Issue.record("Expected deadline") }
    catch { #expect(error as? UnlockLocatorError == .macNotFound) }
    #expect(first.closeCount == 1 && second.closeCount == 0)
    #expect(first.sendCount == 0 && second.sendCount == 0)
}

@Test func frameParserRejectsOversizedAndZeroLengths() {
    for bytes in [[UInt8](repeating: 0, count: 4), [0, 4, 0, 1]] {
        do { _ = try FrameParser.length(Data(bytes)); Issue.record("Expected protocol error") }
        catch { #expect(error as? UnlockSessionError == .protocolError) }
    }
}
