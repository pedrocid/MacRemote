import Foundation
import CoreGraphics
import AppKit

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

    // MARK: - Screen Info

    var screenSize: CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }

    // MARK: - Permissions

    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
