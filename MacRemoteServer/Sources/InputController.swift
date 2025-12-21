import Foundation
import CoreGraphics
import AppKit

// Media key constants from IOKit/hidsystem/ev_keymap.h
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3

/// Controls mouse and keyboard input on macOS using CGEvent API
final class InputController {

    private var currentPosition: CGPoint

    init() {
        currentPosition = NSEvent.mouseLocation
        // Convert from bottom-left to top-left coordinate system
        if let screen = NSScreen.main {
            currentPosition.y = screen.frame.height - currentPosition.y
        }
    }

    // MARK: - Mouse Movement

    func moveMouse(dx: Double, dy: Double) {
        currentPosition.x += CGFloat(dx)
        currentPosition.y += CGFloat(dy)

        // Clamp to screen bounds
        if let screen = NSScreen.main {
            currentPosition.x = max(0, min(currentPosition.x, screen.frame.width))
            currentPosition.y = max(0, min(currentPosition.y, screen.frame.height))
        }

        CGWarpMouseCursorPosition(currentPosition)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Mouse Clicks

    func click(button: RemoteMessage.MouseButton) {
        mouseDown(button: button)
        usleep(10000) // 10ms delay
        mouseUp(button: button)
    }

    func doubleClick(button: RemoteMessage.MouseButton) {
        let (downType, upType, cgButton) = mouseEventTypes(for: button)
        let position = currentPosition

        for clickNumber in 1...2 {
            guard let downEvent = CGEvent(mouseEventSource: nil,
                                          mouseType: downType,
                                          mouseCursorPosition: position,
                                          mouseButton: cgButton),
                  let upEvent = CGEvent(mouseEventSource: nil,
                                        mouseType: upType,
                                        mouseCursorPosition: position,
                                        mouseButton: cgButton) else { continue }

            downEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            upEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))

            downEvent.post(tap: .cgSessionEventTap)
            upEvent.post(tap: .cgSessionEventTap)

            if clickNumber < 2 {
                usleep(50000) // 50ms between clicks
            }
        }
    }

    func mouseDown(button: RemoteMessage.MouseButton) {
        let (downType, _, cgButton) = mouseEventTypes(for: button)

        guard let event = CGEvent(mouseEventSource: nil,
                                  mouseType: downType,
                                  mouseCursorPosition: currentPosition,
                                  mouseButton: cgButton) else { return }
        event.post(tap: .cgSessionEventTap)
    }

    func mouseUp(button: RemoteMessage.MouseButton) {
        let (_, upType, cgButton) = mouseEventTypes(for: button)

        guard let event = CGEvent(mouseEventSource: nil,
                                  mouseType: upType,
                                  mouseCursorPosition: currentPosition,
                                  mouseButton: cgButton) else { return }
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Scrolling

    func scroll(dx: Double, dy: Double) {
        // CGEvent scroll uses discrete scroll units
        let scrollEvent = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32(-dy * 10),
                                  wheel2: Int32(-dx * 10),
                                  wheel3: 0)
        scrollEvent?.post(tap: .cgSessionEventTap)
    }

    // MARK: - Keyboard

    func keyEvent(code: UInt16, down: Bool, flags: UInt64) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: code,
                                  keyDown: down) else { return }

        event.flags = CGEventFlags(rawValue: flags)
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Media Controls

    func mediaAction(_ action: RemoteMessage.MediaAction) {
        let keyCode: Int32
        switch action {
        case .playPause:
            keyCode = NX_KEYTYPE_PLAY
        case .nextTrack:
            keyCode = NX_KEYTYPE_NEXT
        case .previousTrack:
            keyCode = NX_KEYTYPE_PREVIOUS
        case .volumeUp:
            keyCode = NX_KEYTYPE_SOUND_UP
        case .volumeDown:
            keyCode = NX_KEYTYPE_SOUND_DOWN
        case .mute:
            keyCode = NX_KEYTYPE_MUTE
        case .brightnessUp:
            keyCode = NX_KEYTYPE_BRIGHTNESS_UP
        case .brightnessDown:
            keyCode = NX_KEYTYPE_BRIGHTNESS_DOWN
        }
        postMediaKeyEvent(keyCode: keyCode)
    }

    private func postMediaKeyEvent(keyCode: Int32) {
        func doKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: (down ? 0xa00 : 0xb00))
            let data1 = Int((keyCode << 16) | (down ? 0xa00 : 0xb00))

            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }

            event.cgEvent?.post(tap: .cgSessionEventTap)
        }

        doKey(down: true)
        doKey(down: false)
    }

    // MARK: - System Actions

    func systemAction(_ action: RemoteMessage.SystemAction) {
        switch action {
        case .lock:
            lockScreen()
        }
    }

    private func lockScreen() {
        let cgSessionPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

        guard FileManager.default.fileExists(atPath: cgSessionPath) else {
            print("[InputController] CGSession not found at expected path: \(cgSessionPath)")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: cgSessionPath)
        task.arguments = ["-suspend"]
        do {
            try task.run()
            print("[InputController] Lock screen command executed")
        } catch {
            print("[InputController] Failed to lock screen: \(error)")
        }
    }

    // MARK: - Screen Info

    var screenSize: CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }

    // MARK: - Permissions

    static func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        print("[InputController] Accessibility check (prompt=\(prompt)): \(result)")
        return result
    }

    static func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private Helpers

    private func mouseEventTypes(for button: RemoteMessage.MouseButton) -> (CGEventType, CGEventType, CGMouseButton) {
        switch button {
        case .left:
            return (.leftMouseDown, .leftMouseUp, .left)
        case .right:
            return (.rightMouseDown, .rightMouseUp, .right)
        }
    }
}
