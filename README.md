# MacRemote

Control your Mac from your iPhone. Trackpad, keyboard, and media controls over your local network.

## Features

- **Trackpad**: Move cursor, tap to click, double-tap, right-click, scroll
- **Screen Sharing**: View your Mac's screen on your iPhone with H.264 streaming (low/medium/high quality)
- **Media Controls**: Play/pause, next/previous track, volume up/down/mute, brightness up/down
- **Keyboard**: Native iOS keyboard input, quick shortcuts (⌘C, ⌘V, ⌘Z), arrow keys, function keys
- **App Launcher**: Browse and launch Mac apps remotely, with favorites support
- **System Controls**: Lock and unlock the screen remotely
- **Protected Unlock**: The Mac password stays in the Mac Keychain; iOS requires device-owner authentication and a pairing key

## Screenshots

| Trackpad | Screen | Media | Keyboard | Apps | System |
|----------|--------|-------|----------|------|--------|
| Touch to move cursor, tap to click | View Mac screen remotely | Volume, playback, and brightness | Native keyboard + shortcuts | Launch Mac apps | Lock and unlock |

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

### Remote Unlock Setup

1. Open the MacRemote Server menu bar window.
2. Enter the Mac login password under **Remote Unlock** and enable it.
3. Copy the generated pairing key.
4. Connect from iOS, open the System tab, and save that pairing key.
5. Tap **Unlock Mac** and authenticate with Face ID, Touch ID, or the iPhone passcode.

The Mac password remains in the Mac Keychain. The iOS app stores only the pairing token and sends a one-time HMAC response for each unlock request.

### iOS Client

1. Build and run `MacRemoteClient` scheme on your iPhone
2. The app will discover your Mac automatically via Bonjour
3. Tap to connect

## Architecture

```
┌─────────────────┐         WiFi/TCP         ┌─────────────────┐
│   iOS Client    │◄───────────────────────►│   macOS Server  │
│                 │      JSON messages       │   (Menubar)     │
│                 │      + H.264 stream      │                 │
│ • Trackpad UI   │                          │ • CGEvent API   │
│ • Screen View   │                          │ • ScreenCapture │
│ • Media buttons │                          │ • Bonjour       │
│ • Keyboard      │                          │ • TCP Server    │
│ • App Launcher  │                          │ • App List      │
│ • System Ctrl   │                          │                 │
└─────────────────┘                          └─────────────────┘
```

### Protocol

Communication uses JSON messages over TCP with length-prefix framing:

```swift
// Client → Server
enum RemoteMessage {
    case move(dx: Double, dy: Double)
    case click(button: MouseButton)
    case doubleClick(button: MouseButton)
    case scroll(dx: Double, dy: Double)
    case key(code: UInt16, down: Bool, flags: UInt64)
    case media(action: MediaAction)      // playPause, volumeUp, brightnessUp, etc.
    case system(action: SystemAction)    // lock
    case unlock(signature: Data)         // one-time HMAC response
    case requestAppList
    case launchApp(bundleId: String)
    case startScreenStream(quality: StreamQuality)
    case stopScreenStream
}

// Server → Client
enum ServerMessage {
    case connected(screenWidth: Double, screenHeight: Double)
    case pong
    case error(message: String)
    case appList(apps: [AppInfo])
    case screenFrame(frame: ScreenFrame)  // H.264 encoded frame
    case screenStreamStarted
    case screenStreamStopped
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
│       ├── InputController.swift
│       └── ScreenCaptureManager.swift
└── MacRemoteClient/             # iOS app
    ├── Project.swift
    └── Sources/
        ├── MacRemoteClientApp.swift
        ├── ConnectionView.swift
        ├── RemoteControlView.swift
        ├── TrackpadView.swift
        ├── ScreenView.swift
        ├── AppsView.swift
        ├── KeyboardView.swift
        ├── VideoDecoder.swift
        ├── NetworkClient.swift
        └── BonjourBrowser.swift
```

## Permissions

### macOS (Server)

| Permission | Purpose |
|------------|---------|
| Accessibility | Control mouse and keyboard |
| Screen Recording | Screen sharing feature |
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

- [x] Screen sharing (view Mac desktop on iOS) - [#1](https://github.com/pedrocid/MacRemote/issues/1)
- [x] App launcher
- [ ] Multi-touch gestures
- [ ] Custom shortcuts
- [ ] Widget for iOS

## License

MIT

## Acknowledgments

Built with:
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/)
- [VideoToolbox](https://developer.apple.com/documentation/videotoolbox) (H.264 encoding/decoding)
- [Network.framework](https://developer.apple.com/documentation/network)
- [Bonjour](https://developer.apple.com/bonjour/)
