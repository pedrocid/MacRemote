import SwiftUI

/// View that displays the Mac screen stream and allows touch-based control
struct ScreenView: View {
    @ObservedObject var client: NetworkClient
    @StateObject private var viewModel = ScreenViewModel()
    @State private var selectedQuality: RemoteMessage.StreamQuality = .medium

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if client.isScreenStreaming {
                    // Screen display
                    screenDisplay(in: geometry)
                } else {
                    // Start streaming UI
                    startStreamingView
                }

                // Overlay controls (when streaming)
                if client.isScreenStreaming {
                    VStack {
                        streamingControls
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            setupFrameCallback()
        }
        .onDisappear {
            if client.isScreenStreaming {
                client.stopScreenStream()
            }
            viewModel.cleanup()
        }
    }

    // MARK: - Start Streaming View

    private var startStreamingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "display")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text(String(localized: "screen_sharing"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "screen_sharing_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Quality picker
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "quality"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Quality", selection: $selectedQuality) {
                    Text(String(localized: "quality_low")).tag(RemoteMessage.StreamQuality.low)
                    Text(String(localized: "quality_medium")).tag(RemoteMessage.StreamQuality.medium)
                    Text(String(localized: "quality_high")).tag(RemoteMessage.StreamQuality.high)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 40)

            Button {
                client.startScreenStream(quality: selectedQuality)
            } label: {
                Label(String(localized: "start_streaming"), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Screen Display

    @ViewBuilder
    private func screenDisplay(in geometry: GeometryProxy) -> some View {
        if let image = viewModel.currentFrame {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDrag(value: value, in: geometry, imageSize: image.size)
                        }
                        .onEnded { value in
                            handleDragEnd(value: value, in: geometry, imageSize: image.size)
                        }
                )
                .onTapGesture(count: 2) {
                    // Double tap for double click
                    client.doubleClick()
                }
                .onTapGesture(count: 1) {
                    // Single tap for click
                    client.click()
                }
        } else {
            // Loading state
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(String(localized: "waiting_for_frames"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.9))
        }
    }

    // MARK: - Streaming Controls

    private var streamingControls: some View {
        HStack {
            // Quality indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("\(viewModel.frameWidth)×\(viewModel.frameHeight)")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)

            Spacer()

            // Stop button
            Button {
                client.stopScreenStream()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(22)
            }
        }
        .padding()
    }

    // MARK: - Gesture Handling

    @State private var lastTranslation: CGSize = .zero
    @State private var isDragging = false

    private func handleDrag(value: DragGesture.Value, in geometry: GeometryProxy, imageSize: CGSize) {
        if !isDragging {
            lastTranslation = .zero
            isDragging = true
        }

        // Calculate the delta since last update (not cumulative translation)
        let dx = value.translation.width - lastTranslation.width
        let dy = value.translation.height - lastTranslation.height
        lastTranslation = CGSize(width: value.translation.width, height: value.translation.height)

        // Scale factor for mouse sensitivity
        let scaleFactor = 1.5

        client.move(dx: dx * scaleFactor, dy: dy * scaleFactor)
    }

    private func handleDragEnd(value: DragGesture.Value, in geometry: GeometryProxy, imageSize: CGSize) {
        isDragging = false
        lastTranslation = .zero

        // Check if this was a tap (minimal movement)
        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
        if distance < 5 {
            // This was a tap, handled by onTapGesture
        }
    }

    // MARK: - Frame Callback

    private func setupFrameCallback() {
        client.onScreenFrameReceived = { [weak viewModel] frame in
            viewModel?.decodeFrame(frame)
        }
    }
}

// MARK: - Screen View Model

@MainActor
final class ScreenViewModel: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var frameWidth: Int = 0
    @Published var frameHeight: Int = 0

    private let decoder = VideoDecoder()

    init() {
        decoder.onFrameDecoded = { [weak self] image in
            self?.currentFrame = image
        }
    }

    func decodeFrame(_ frame: ScreenFrame) {
        frameWidth = frame.width
        frameHeight = frame.height
        decoder.decodeFrame(frame)
    }

    func cleanup() {
        decoder.cleanup()
        currentFrame = nil
    }
}
