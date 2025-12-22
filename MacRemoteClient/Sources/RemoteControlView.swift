import SwiftUI

/// Main remote control interface with trackpad and buttons
struct RemoteControlView: View {
    @ObservedObject var client: NetworkClient
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Mode", selection: $selectedTab) {
                Image(systemName: "hand.point.up.fill").tag(0)
                Image(systemName: "display").tag(1)
                Image(systemName: "speaker.wave.2.fill").tag(2)
                Image(systemName: "keyboard").tag(3)
                Image(systemName: "square.grid.2x2").tag(4)
                Image(systemName: "gearshape.fill").tag(5)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Content
            TabView(selection: $selectedTab) {
                trackpadTab.tag(0)
                screenTab.tag(1)
                mediaTab.tag(2)
                keyboardTab.tag(3)
                appsTab.tag(4)
                systemTab.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    // MARK: - Screen Tab

    private var screenTab: some View {
        ScreenView(client: client)
    }

    // MARK: - Apps Tab

    private var appsTab: some View {
        AppsView(client: client)
    }

    // MARK: - Trackpad Tab

    private var trackpadTab: some View {
        VStack(spacing: 16) {
            // Main trackpad
            TrackpadView(client: client)
                .frame(maxHeight: .infinity)

            // Scroll area
            ScrollTrackpadView(client: client)
                .frame(height: 70)

            // Mouse buttons
            mouseButtons
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
                    .frame(height: 56)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Right click
            Button {
                client.click(button: .right)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "computermouse.fill")
                        .font(.title2)
                    Text("Right")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Media Tab

    private var mediaTab: some View {
        VStack(spacing: 24) {
            Spacer()

            // Volume controls
            HStack(spacing: 40) {
                MediaButton(icon: "speaker.minus.fill", label: "Vol -") {
                    client.volumeDown()
                }

                MediaButton(icon: "speaker.slash.fill", label: "Mute") {
                    client.mute()
                }

                MediaButton(icon: "speaker.plus.fill", label: "Vol +") {
                    client.volumeUp()
                }
            }

            Divider()
                .padding(.horizontal, 40)

            // Playback controls
            HStack(spacing: 40) {
                MediaButton(icon: "backward.fill", label: "Previous") {
                    client.previousTrack()
                }

                MediaButton(icon: "playpause.fill", label: "Play/Pause", large: true) {
                    client.playPause()
                }

                MediaButton(icon: "forward.fill", label: "Next") {
                    client.nextTrack()
                }
            }

            Divider()
                .padding(.horizontal, 40)

            // Brightness controls
            HStack(spacing: 40) {
                MediaButton(icon: "sun.min.fill", label: "Bright -") {
                    client.brightnessDown()
                }

                MediaButton(icon: "sun.max.fill", label: "Bright +") {
                    client.brightnessUp()
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Keyboard Tab

    private var keyboardTab: some View {
        DirectKeyboardView(client: client, selectedTab: $selectedTab)
    }

    // MARK: - System Tab

    private var systemTab: some View {
        SystemView(client: client)
    }
}

// MARK: - Media Button

struct MediaButton: View {
    let icon: String
    let label: String
    var large: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(large ? .largeTitle : .title2)
                Text(label)
                    .font(.caption)
            }
            .frame(width: large ? 90 : 70, height: large ? 90 : 70)
            .background(Color(.systemGray5))
            .cornerRadius(large ? 45 : 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Direct Keyboard View

struct DirectKeyboardView: View {
    @ObservedObject var client: NetworkClient
    @Binding var selectedTab: Int
    @FocusState private var isKeyboardActive: Bool
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 16) {
            // Hidden text field that captures keyboard input
            TextField("", text: $inputText)
                .focused($isKeyboardActive)
                .opacity(0.01)
                .frame(height: 1)
                .onChange(of: inputText) { oldValue, newValue in
                    handleTextChange(from: oldValue, to: newValue)
                }

            Spacer()

            // Keyboard status
            VStack(spacing: 12) {
                Image(systemName: isKeyboardActive ? "keyboard" : "keyboard.badge.ellipsis")
                    .font(.system(size: 60))
                    .foregroundStyle(isKeyboardActive ? .blue : .secondary)

                Text(isKeyboardActive ? "Type on the keyboard below" : "Tap to activate keyboard")
                    .font(.headline)
                    .foregroundStyle(isKeyboardActive ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(Color(.systemGray6))
            .cornerRadius(20)
            .onTapGesture {
                isKeyboardActive = true
            }

            // Quick action buttons
            HStack(spacing: 12) {
                QuickActionButton(label: "Esc") {
                    client.keyPress(code: KeyCodes.escape)
                }
                QuickActionButton(label: "Tab") {
                    client.keyPress(code: KeyCodes.tab)
                }
                QuickActionButton(label: "⌘C") {
                    client.send(.key(code: KeyCodes.c, down: true, flags: KeyCodes.maskCommand))
                    client.send(.key(code: KeyCodes.c, down: false, flags: KeyCodes.maskCommand))
                }
                QuickActionButton(label: "⌘V") {
                    client.send(.key(code: KeyCodes.v, down: true, flags: KeyCodes.maskCommand))
                    client.send(.key(code: KeyCodes.v, down: false, flags: KeyCodes.maskCommand))
                }
                QuickActionButton(label: "⌘Z") {
                    client.send(.key(code: KeyCodes.z, down: true, flags: KeyCodes.maskCommand))
                    client.send(.key(code: KeyCodes.z, down: false, flags: KeyCodes.maskCommand))
                }
            }

            // Arrow keys
            HStack(spacing: 12) {
                QuickActionButton(icon: "arrow.left") {
                    client.keyPress(code: KeyCodes.leftArrow)
                }
                QuickActionButton(icon: "arrow.down") {
                    client.keyPress(code: KeyCodes.downArrow)
                }
                QuickActionButton(icon: "arrow.up") {
                    client.keyPress(code: KeyCodes.upArrow)
                }
                QuickActionButton(icon: "arrow.right") {
                    client.keyPress(code: KeyCodes.rightArrow)
                }
                Spacer()
                QuickActionButton(icon: "delete.left") {
                    client.keyPress(code: KeyCodes.delete)
                }
                QuickActionButton(icon: "return") {
                    client.keyPress(code: KeyCodes.returnKey)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Auto-activate keyboard when tab is selected
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isKeyboardActive = true
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Hide keyboard when switching away from keyboard tab
            if newTab != 3 {
                isKeyboardActive = false
            }
        }
    }

    private func handleTextChange(from oldValue: String, to newValue: String) {
        // Ignore when we programmatically clear the field
        if newValue.isEmpty {
            return
        }
        if newValue.count > oldValue.count {
            // Character added
            if let char = newValue.last {
                sendCharacter(char)
            }
        }
        // Clear the text field to keep it ready for next input
        inputText = ""
    }

    private func sendCharacter(_ char: Character) {
        if let keyCode = KeyCodes.code(for: char) {
            let needsShift = char.isUppercase || KeyCodes.shiftCharacters.contains(char)
            let flags: UInt64 = needsShift ? KeyCodes.maskShift : 0
            client.send(.key(code: keyCode, down: true, flags: flags))
            client.send(.key(code: keyCode, down: false, flags: flags))
        }
    }
}

struct QuickActionButton: View {
    var label: String? = nil
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                } else if let label = label {
                    Text(label)
                }
            }
            .font(.system(.body, design: .rounded, weight: .medium))
            .frame(minWidth: 44, minHeight: 44)
            .background(Color(.systemGray5))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System View

struct SystemView: View {
    @ObservedObject var client: NetworkClient
    @State private var showingLockConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Lock Screen Button
            Button {
                showingLockConfirmation = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                    Text(String(localized: "lock_screen"))
                        .font(.headline)
                }
                .frame(width: 140, height: 140)
                .background(Color(.systemGray5))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                String(localized: "lock_screen_confirmation_title"),
                isPresented: $showingLockConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "lock_screen_confirm"), role: .destructive) {
                    client.lockScreen()
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "lock_screen_confirmation_message"))
            }

            Spacer()
        }
        .padding()
    }
}
