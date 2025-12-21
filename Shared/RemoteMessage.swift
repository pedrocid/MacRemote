import Foundation

/// Messages sent from iOS client to macOS server
enum RemoteMessage: Codable {
    case move(dx: Double, dy: Double)
    case click(button: MouseButton)
    case doubleClick(button: MouseButton)
    case mouseDown(button: MouseButton)
    case mouseUp(button: MouseButton)
    case scroll(dx: Double, dy: Double)
    case key(code: UInt16, down: Bool, flags: UInt64)
    case media(action: MediaAction)
    case ping

    enum MouseButton: String, Codable {
        case left
        case right
    }

    enum MediaAction: String, Codable {
        case playPause
        case nextTrack
        case previousTrack
        case volumeUp
        case volumeDown
        case mute
        case brightnessUp
        case brightnessDown
    }
}

/// Messages sent from macOS server to iOS client
enum ServerMessage: Codable {
    case connected(screenWidth: Double, screenHeight: Double)
    case pong
    case error(message: String)
}

/// Protocol message wrapper with length prefix for TCP framing
struct MessageFrame {
    static func encode<T: Encodable>(_ message: T) throws -> Data {
        let jsonData = try JSONEncoder().encode(message)
        var length = UInt32(jsonData.count).bigEndian
        var frameData = Data(bytes: &length, count: 4)
        frameData.append(jsonData)
        return frameData
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}
