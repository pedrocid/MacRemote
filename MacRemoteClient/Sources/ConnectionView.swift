import SwiftUI

/// View for discovering and connecting to Mac servers
struct ConnectionView: View {
    @ObservedObject var browser: BonjourBrowser
    @ObservedObject var client: NetworkClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if browser.servers.isEmpty {
                    if browser.isSearching {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Searching for Macs...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Macs Found",
                            systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                            description: Text("Make sure MacRemote Server is running on your Mac")
                        )
                    }
                } else {
                    Section("Available Macs") {
                        ForEach(browser.servers) { server in
                            Button {
                                client.connect(to: server.endpoint)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                        .font(.title2)
                                        .foregroundStyle(.blue)

                                    VStack(alignment: .leading) {
                                        Text(server.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("Tap to connect")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        browser.startBrowsing()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                browser.startBrowsing()
            }
            .onDisappear {
                browser.stopBrowsing()
            }
        }
    }
}
