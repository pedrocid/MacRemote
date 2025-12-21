# MacRemote

Control your Mac from your iPhone. Trackpad, keyboard, and media controls over your local network.

## Features

- **Trackpad**: Move cursor, tap to click, double-tap, right-click, scroll
- **Media Controls**: Play/pause, next/previous track, volume up/down/mute
- **Keyboard**: Native iOS keyboard input, quick shortcuts (⌘C, ⌘V, ⌘Z), arrow keys, function keys

## Screenshots

| Trackpad | Media | Keyboard |
|----------|-------|----------|
| Touch to move cursor, tap to click | Volume and playback controls | Native keyboard + shortcuts |

## Requirements

- **macOS**: 14.0+
- **iOS**: 17.0+
- **Network**: Both devices on the same WiFi network

## Installation

### Prerequisites

- [Tuist](https://tuist.io) installed (`brew install tuist`)
- Xcode 15+

### Build

```bash
git clone https://github.com/pedrocid/MacRemote.git
cd MacRemote
tuist generate
open MacRemote.xcworkspace
```

### macOS Server

1. Build and run `MacRemoteServer` scheme
2. Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility)
3. Click "Start Server" in the menubar app

### iOS Client

1. Build and run `MacRemoteClient` scheme on your iPhone
2. The app will discover your Mac automatically via Bonjour
3. Tap to connect

## Architecture

```
┌─────────────────┐         WiFi/TCP         ┌─────────────────┐
│   iOS Client    │◄───────────────────────►│   macOS Server  │
│                 │      JSON messages       │   (Menubar)     │
│                 │                          │                 │
│ • Trackpad UI   │                          │ • CGEvent API   │
│ • Media buttons │                          │ • Bonjour       │
│ • Keyboard      │                          │ • TCP Server    │
└─────────────────┘                          └─────────────────┘
```

### Protocol

Communication uses JSON messages over TCP with length-prefix framing:

```swift
// Client → Server
enum RemoteMessage {
    case move(dx: Double, dy: Double)
    case click(button: MouseButton)
    case scroll(dx: Double, dy: Double)
    case key(code: UInt16, down: Bool, flags: UInt64)
    case media(action: MediaAction)  // playPause, volumeUp, etc.
}

// Server → Client
enum ServerMessage {
    case connected(screenWidth: Double, screenHeight: Double)
    case pong
    case error(message: String)
}
```

### Project Structure

```
MacRemote/
├── Workspace.swift              # Tuist workspace
├── Tuist/Config.swift
├── Shared/                      # Shared code
│   ├── RemoteMessage.swift      # Protocol messages
│   └── NetworkConstants.swift
├── MacRemoteServer/             # macOS menubar app
│   ├── Project.swift
│   └── Sources/
│       ├── MacRemoteServerApp.swift
│       ├── ServerManager.swift
│       ├── NetworkServer.swift
│       ├── BonjourAdvertiser.swift
│       └── InputController.swift
└── MacRemoteClient/             # iOS app
    ├── Project.swift
    └── Sources/
        ├── MacRemoteClientApp.swift
        ├── RemoteControlView.swift
        ├── TrackpadView.swift
        ├── NetworkClient.swift
        └── BonjourBrowser.swift
```

## Permissions

### macOS (Server)

| Permission | Purpose |
|------------|---------|
| Accessibility | Control mouse and keyboard |
| Local Network | Bonjour discovery and TCP server |

### iOS (Client)

| Permission | Purpose |
|------------|---------|
| Local Network | Discover and connect to Mac |

## Troubleshooting

### "Accessibility permission required"

1. Open System Settings → Privacy & Security → Accessibility
2. Add or enable "MacRemote Server"
3. Click "Refresh" in the app

### Can't find Mac

- Ensure both devices are on the same WiFi network
- Check that the server is running (antenna icon in menubar)
- Try restarting the server

### Connection drops

- Check WiFi stability
- Ensure Mac doesn't go to sleep

## Roadmap

- [ ] Screen sharing (view Mac desktop on iOS) - [#1](https://github.com/pedrocid/MacRemote/issues/1)
- [ ] Multi-touch gestures
- [ ] Custom shortcuts
- [ ] Widget for iOS

## License

MIT

## Acknowledgments

Built with:
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/) (planned)
- [Network.framework](https://developer.apple.com/documentation/network)
- [Bonjour](https://developer.apple.com/bonjour/)
