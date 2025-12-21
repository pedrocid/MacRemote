import SwiftUI

/// Trackpad-like touch surface for controlling the mouse
struct TrackpadView: View {
    @ObservedObject var client: NetworkClient

    @State private var lastLocation: CGPoint?
    @State private var isDragging = false
    @State private var tapCount = 0
    @State private var lastTapTime: Date?

    private let sensitivity: Double = 1.5
    private let scrollSensitivity: Double = 0.5
    private let doubleTapThreshold: TimeInterval = 0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                    )

                // Instructions
                if !client.isConnected {
                    Text("Not Connected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack {
                        Image(systemName: "hand.point.up.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("Touch to move cursor")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value, in: geometry.size)
                    }
                    .onEnded { _ in
                        handleDragEnd()
                    }
            )
            .simultaneousGesture(
                // Two finger scroll
                MagnificationGesture()
                    .onChanged { _ in }
            )
        }
        .aspectRatio(4/3, contentMode: .fit)
    }

    private func handleDrag(_ value: DragGesture.Value, in size: CGSize) {
        let currentLocation = value.location

        if let last = lastLocation {
            let dx = (currentLocation.x - last.x) * sensitivity
            let dy = (currentLocation.y - last.y) * sensitivity

            if abs(dx) > 0.1 || abs(dy) > 0.1 {
                client.move(dx: dx, dy: dy)
                isDragging = true
            }
        } else {
            // First touch - check for tap
            isDragging = false
        }

        lastLocation = currentLocation
    }

    private func handleDragEnd() {
        defer {
            lastLocation = nil
        }

        // If we didn't drag, it's a tap
        if !isDragging {
            let now = Date()

            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < doubleTapThreshold {
                // Double tap
                client.doubleClick()
                lastTapTime = nil
                tapCount = 0
            } else {
                // Single tap - wait to see if double tap
                lastTapTime = now
                tapCount = 1

                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold) { [self] in
                    if self.tapCount == 1 {
                        client.click()
                        self.tapCount = 0
                    }
                }
            }
        }

        isDragging = false
    }
}

/// Two-finger scroll gesture view
struct ScrollTrackpadView: View {
    @ObservedObject var client: NetworkClient

    @State private var lastTranslation: CGSize = .zero

    private let scrollSensitivity: Double = 0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                    )

                VStack {
                    Image(systemName: "arrow.up.and.down")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Scroll")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let dy = (value.translation.height - lastTranslation.height) * scrollSensitivity
                        let dx = (value.translation.width - lastTranslation.width) * scrollSensitivity
                        client.scroll(dx: dx, dy: dy)
                        lastTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastTranslation = .zero
                    }
            )
        }
    }
}
