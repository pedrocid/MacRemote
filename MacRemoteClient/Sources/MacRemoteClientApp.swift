import SwiftUI

@main
struct MacRemoteClientApp: App {
    @StateObject private var browser = BonjourBrowser()
    @StateObject private var client = NetworkClient()
    @State private var showConnectionSheet = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RemoteControlView(client: client)
                    .navigationTitle("MacRemote")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            connectionStatusButton
                        }
                    }
            }
            .sheet(isPresented: $showConnectionSheet) {
                ConnectionView(browser: browser, client: client)
            }
            .onAppear {
                if !client.isConnected {
                    showConnectionSheet = true
                }
            }
        }
    }

    private var connectionStatusButton: some View {
        Button {
            if client.isConnected {
                client.disconnect()
            }
            showConnectionSheet = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(client.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(client.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
            }
        }
    }
}
