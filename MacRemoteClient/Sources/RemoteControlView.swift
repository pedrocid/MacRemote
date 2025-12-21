import SwiftUI

/// Main remote control interface with trackpad and buttons
struct RemoteControlView: View {
    @ObservedObject var client: NetworkClient
    @State private var showKeyboard = false

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .sheet(isPresented: $showKeyboard) {
            NavigationStack {
                KeyboardView(client: client)
                    .navigationTitle("Keyboard")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showKeyboard = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: 16) {
            // Main trackpad
            TrackpadView(client: client)
                .frame(maxHeight: .infinity)

            // Scroll area
            ScrollTrackpadView(client: client)
                .frame(height: 80)

            // Mouse buttons
            mouseButtons

            // Keyboard toggle
            keyboardButton
        }
        .padding()
    }

    private var landscapeLayout: some View {
        HStack(spacing: 16) {
            // Main trackpad
            TrackpadView(client: client)
                .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                // Scroll area
                ScrollTrackpadView(client: client)
                    .frame(height: 100)

                // Mouse buttons
                mouseButtons

                Spacer()

                // Keyboard toggle
                keyboardButton
            }
            .frame(width: 160)
        }
        .padding()
    }

    private var mouseButtons: some View {
        HStack(spacing: 16) {
            // Left click
            Button {
                client.click(button: .left)
            } label: {
                Image(systemName: "computermouse.fill")
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        client.send(.mouseDown(button: .left))
                    }
            )

            // Right click
            Button {
                client.click(button: .right)
            } label: {
                VStack {
                    Image(systemName: "computermouse.fill")
                        .font(.title)
                    Text("Right")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    private var keyboardButton: some View {
        Button {
            showKeyboard = true
        } label: {
            Label("Keyboard", systemImage: "keyboard")
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(.systemGray5))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
