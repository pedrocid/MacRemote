import Foundation
import AppKit
import Network

/// Main controller that coordinates the server, Bonjour, and input handling
@MainActor
final class ServerManager: ObservableObject {

    private let server = NetworkServer()
    private let advertiser = BonjourAdvertiser()
    private let inputController = InputController()
    private let screenCaptureManager = ScreenCaptureManager()

    // Track which clients are receiving screen stream
    private var streamingClients = Set<ObjectIdentifier>()

    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var hasAccessibilityPermission = false
    @Published var hasScreenRecordingPermission = false
    @Published var isScreenStreaming = false
    @Published var lastError: String?

    init() {
        setupServerCallbacks()
        setupScreenCaptureCallbacks()
        checkPermissions()
    }

    // MARK: - Server Control

    func start() {
        guard hasAccessibilityPermission else {
            lastError = "Accessibility permission required"
            _ = InputController.checkAccessibilityPermission()
            return
        }

        do {
            try server.start()

            // Wait a bit for the server to be ready, then advertise
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.server.isRunning else { return }
                self.advertiser.startAdvertising(port: self.server.port)
                self.isRunning = true
            }
        } catch {
            lastError = error.localizedDescription
            print("[ServerManager] Failed to start: \(error)")
        }
    }

    func stop() {
        // Stop screen streaming if active
        Task {
            await stopScreenStreaming()
        }
        advertiser.stopAdvertising()
        server.stop()
        isRunning = false
        connectedClients = 0
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Permissions

    func checkPermissions() {
        hasAccessibilityPermission = InputController.checkAccessibilityPermission(prompt: false)
        Task {
            await screenCaptureManager.checkPermission()
            hasScreenRecordingPermission = screenCaptureManager.hasScreenRecordingPermission
        }
    }

    func requestAccessibilityPermission() {
        // Open System Preferences directly to Accessibility
        InputController.openAccessibilityPreferences()
    }

    func requestScreenRecordingPermission() {
        // Open System Preferences to Screen Recording
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Screen Streaming

    private func startScreenStreaming(quality: RemoteMessage.StreamQuality, for connection: NWConnection) {
        let clientId = ObjectIdentifier(connection)
        streamingClients.insert(clientId)

        // If not already streaming, start the capture
        if !isScreenStreaming {
            Task {
                do {
                    try await screenCaptureManager.startStreaming(quality: quality)
                    isScreenStreaming = true
                    server.send(.screenStreamStarted, to: connection)
                    print("[ServerManager] Screen streaming started for client")
                } catch {
                    print("[ServerManager] Failed to start screen streaming: \(error)")
                    server.send(.error(message: "Failed to start screen streaming: \(error.localizedDescription)"), to: connection)
                    streamingClients.remove(clientId)
                }
            }
        } else {
            server.send(.screenStreamStarted, to: connection)
        }
    }

    private func stopScreenStreamingForClient(_ connection: NWConnection) {
        let clientId = ObjectIdentifier(connection)
        streamingClients.remove(clientId)

        // If no more clients need streaming, stop capture
        if streamingClients.isEmpty {
            Task {
                await stopScreenStreaming()
            }
        }

        server.send(.screenStreamStopped, to: connection)
    }

    private func stopScreenStreaming() async {
        guard isScreenStreaming else { return }
        await screenCaptureManager.stopStreaming()
        isScreenStreaming = false
        streamingClients.removeAll()
        print("[ServerManager] Screen streaming stopped")
    }

    private func setupScreenCaptureCallbacks() {
        screenCaptureManager.onFrameEncoded = { [weak self] frame in
            guard let self = self else { return }
            // Send frame to all streaming clients
            Task { @MainActor in
                self.server.broadcast(.screenFrame(frame: frame))
            }
        }
    }

    // MARK: - Private

    private func setupServerCallbacks() {
        server.onClientConnected = { [weak self] in
            self?.connectedClients = self?.server.connectedClientsCount ?? 0

            // Send screen info to new client
            let screenSize = self?.inputController.screenSize ?? CGSize(width: 1920, height: 1080)
            self?.server.broadcast(.connected(screenWidth: screenSize.width, screenHeight: screenSize.height))
        }

        server.onClientDisconnected = { [weak self] in
            self?.connectedClients = self?.server.connectedClientsCount ?? 0
        }

        server.onMessageReceived = { [weak self] message, connection in
            self?.handleMessage(message, from: connection)
        }

        server.onError = { [weak self] error in
            self?.lastError = error.localizedDescription
            self?.isRunning = false
        }
    }

    private func handleMessage(_ message: RemoteMessage, from connection: NWConnection) {
        switch message {
        case .move(let dx, let dy):
            inputController.moveMouse(dx: dx, dy: dy)

        case .click(let button):
            inputController.click(button: button)

        case .doubleClick(let button):
            inputController.doubleClick(button: button)

        case .mouseDown(let button):
            inputController.mouseDown(button: button)

        case .mouseUp(let button):
            inputController.mouseUp(button: button)

        case .scroll(let dx, let dy):
            inputController.scroll(dx: dx, dy: dy)

        case .key(let code, let down, let flags):
            inputController.keyEvent(code: code, down: down, flags: flags)

        case .media(let action):
            inputController.mediaAction(action)

        case .system(let action):
            inputController.systemAction(action)

        case .ping:
            server.send(.pong, to: connection)

        case .requestAppList:
            print("[ServerManager] App list requested")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let apps = self.inputController.getInstalledApps()
                print("[ServerManager] Sending \(apps.count) apps")
                self.server.send(.appList(apps: apps), to: connection)
            }

        case .launchApp(let bundleId):
            if !inputController.launchApp(bundleId: bundleId) {
                server.send(.error(message: "Failed to launch app: \(bundleId)"), to: connection)
            }

        case .startScreenStream(let quality):
            print("[ServerManager] Screen stream requested with quality: \(quality)")
            startScreenStreaming(quality: quality, for: connection)

        case .stopScreenStream:
            print("[ServerManager] Screen stream stop requested")
            stopScreenStreamingForClient(connection)
        }
    }
}
