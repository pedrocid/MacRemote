import SwiftUI

@main
struct MacRemoteServerApp: App {
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(serverManager: serverManager)
        } label: {
            Image(systemName: serverManager.isRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @ObservedObject var serverManager: ServerManager
    @State private var unlockPassword = ""
    @State private var unlockConfigurationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                Text("MacRemote Server")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Divider()

            // Status
            HStack {
                Circle()
                    .fill(serverManager.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serverManager.isRunning ? "Running" : "Stopped")
                    .foregroundStyle(.secondary)
            }

            if serverManager.isRunning {
                HStack {
                    Image(systemName: "iphone")
                    Text("\(serverManager.connectedClients) client(s) connected")
                        .foregroundStyle(.secondary)
                }
            }

            // Permissions Warning
            if !serverManager.hasAccessibilityPermission {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Accessibility permission required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Open Settings") {
                        serverManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Refresh") {
                        serverManager.checkPermissions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Error
            if let error = serverManager.lastError {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Remote Unlock", systemImage: "lock.open.fill")
                    .font(.headline)

                if serverManager.isRemoteUnlockConfigured {
                    Text("Enabled. The Mac password is stored only in this Mac's Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let pairingKey = serverManager.pairingKey {
                        Text("Pairing key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pairingKey)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)

                        Button("Copy Pairing Key") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pairingKey, forType: .string)
                        }
                        .controlSize(.small)
                    }

                    Button("Disable Remote Unlock", role: .destructive) {
                        serverManager.disableRemoteUnlock()
                        unlockPassword = ""
                    }
                    .controlSize(.small)
                } else {
                    SecureField("Mac login password", text: $unlockPassword)
                        .textFieldStyle(.roundedBorder)

                    Text("The password never leaves this Mac. Pairing and device authentication are required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Enable Remote Unlock") {
                        if serverManager.configureRemoteUnlock(password: unlockPassword) {
                            unlockPassword = ""
                            unlockConfigurationError = nil
                        } else {
                            unlockConfigurationError = "Enter your Mac login password."
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let unlockConfigurationError {
                    Text(unlockConfigurationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Controls
            Button(serverManager.isRunning ? "Stop Server" : "Start Server") {
                serverManager.toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(serverManager.isRunning ? .red : .green)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .frame(width: 320)
    }
}
