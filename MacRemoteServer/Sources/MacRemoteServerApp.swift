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
        .frame(width: 240)
    }
}
