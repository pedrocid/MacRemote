import Foundation
import Testing
@testable import ServerUnlockLogic

@Test func pingRoundTripsThroughMessageFrame() throws {
    let frame = try MessageFrame.encode(RemoteMessage.ping)
    let payload = Data(frame.dropFirst(4))
    let message = try MessageFrame.decode(payload, as: RemoteMessage.self)
    guard case .ping = message else {
        Issue.record("Expected ping message")
        return
    }
}
