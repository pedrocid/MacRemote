# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project (requires Tuist: brew install tuist)
tuist generate

# Open workspace
open MacRemote.xcworkspace

# Build from command line
xcodebuild -workspace MacRemote.xcworkspace -scheme MacRemoteServer -configuration Debug build
xcodebuild -workspace MacRemote.xcworkspace -scheme MacRemoteClient -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Architecture

MacRemote is a remote control app: **iOS Client** controls **macOS Server** over local network.

```
iOS Client ←→ TCP (JSON + 4-byte length prefix) ←→ macOS Server
                    Bonjour Discovery
```

### Key Components

**Shared/** - Protocol definitions shared between client and server
- `RemoteMessage.swift` - Client→Server messages (move, click, scroll, key, media)
- `NetworkConstants.swift` - Service type `_macremote._tcp`, port 5150

**MacRemoteServer/** - macOS menubar app (LSUIElement=true, no sandbox)
- `ServerManager.swift` - Orchestrates server, Bonjour, input; checks accessibility permission
- `NetworkServer.swift` - TCP server using `NWListener`
- `InputController.swift` - Mouse/keyboard injection via `CGEvent` API
- `BonjourAdvertiser.swift` - Service publication via `NetService`

**MacRemoteClient/** - iOS app
- `NetworkClient.swift` - TCP client using `NWConnection`
- `BonjourBrowser.swift` - Service discovery using `NWBrowser`
- `TrackpadView.swift` - Gesture handling for mouse control
- `RemoteControlView.swift` - Tab container with embedded keyboard input

### Message Framing

All TCP messages use 4-byte big-endian length prefix + JSON payload. See `MessageFrame` in RemoteMessage.swift.

## Development Notes

- **Swift 6.0** configured in Tuist/Config.swift
- **No external dependencies** - only Apple frameworks (Network, CoreGraphics, SwiftUI, AppKit)
- **Logging convention**: Print with bracketed prefix `[Server]`, `[Client]`, `[Bonjour]`
- **Thread safety**: Network/input use `.userInteractive` dispatch queues; UI updates dispatch to main

### macOS Server Requirements
- Accessibility permission required for CGEvent input injection
- Hardened runtime enabled, sandbox disabled
- Network server/client entitlements

### iOS Client Requirements
- Local network permission (NSLocalNetworkUsageDescription in Info.plist)
- Bonjour service types declared (NSBonjourServices)

## Localization

User-facing strings must be localized in English and Spanish:
- `MacRemoteClient/Resources/Localizable.xcstrings`

## Testing macOS Server Changes

When making changes to the macOS server (MacRemoteServer), after verifying the build succeeds:

```bash
# Build, copy to Applications, and launch
xcodebuild -workspace MacRemote.xcworkspace -scheme MacRemoteServer -configuration Debug build && \
cp -R ~/Library/Developer/Xcode/DerivedData/MacRemote-*/Build/Products/Debug/MacRemoteServer.app /Applications/ && \
open /Applications/MacRemoteServer.app
```

This ensures you test with the latest version running from Applications.

## Adding New Features

When adding new remote control actions:
1. Add case to `RemoteMessage` enum in `Shared/RemoteMessage.swift`
2. Handle the message in `ServerManager.handleMessage()`
3. Implement the action in `InputController.swift`
4. Add UI in the appropriate iOS view
5. Add localized strings for any user-facing text
