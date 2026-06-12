import Foundation
import CryptoKit
import LocalAuthentication
import Network

/// TCP Client that connects to a MacRemote server
final class NetworkClient: ObservableObject {

    @Published var isConnected = false
    @Published var screenSize: CGSize = .zero
    @Published var connectionError: String?
    @Published var apps: [AppInfo] = []
    @Published var isLoadingApps = false
    @Published var isScreenStreaming = false
    @Published private(set) var isUnlockAvailable = false
    @Published private(set) var hasUnlockPairingKey = false
    @Published var unlockStatus: String?
    @Published var isAuthenticatingForUnlock = false

    // Callback for received screen frames
    var onScreenFrameReceived: ((ScreenFrame) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.macremote.client", qos: .userInteractive)
    private let unlockCredentialStore = UnlockCredentialStore()
    private var unlockChallenge: Data?

    init() {
        hasUnlockPairingKey = unlockCredentialStore.hasToken
    }

    // MARK: - Connection

    func connect(to endpoint: NWEndpoint) {
        disconnect()

        connection = NWConnection(to: endpoint, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.connectionError = nil
                    self?.startReceiving()
                    print("[Client] Connected")

                case .failed(let error):
                    self?.isConnected = false
                    self?.connectionError = error.localizedDescription
                    print("[Client] Failed: \(error)")

                case .cancelled:
                    self?.isConnected = false
                    print("[Client] Cancelled")

                default:
                    break
                }
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    // MARK: - Sending Messages

    func send(_ message: RemoteMessage) {
        guard let connection = connection, isConnected else { return }

        do {
            let data = try MessageFrame.encode(message)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("[Client] Send error: \(error)")
                }
            })
        } catch {
            print("[Client] Encode error: \(error)")
        }
    }

    func move(dx: Double, dy: Double) {
        send(.move(dx: dx, dy: dy))
    }

    func click(button: RemoteMessage.MouseButton = .left) {
        send(.click(button: button))
    }

    func doubleClick(button: RemoteMessage.MouseButton = .left) {
        send(.doubleClick(button: button))
    }

    func scroll(dx: Double, dy: Double) {
        send(.scroll(dx: dx, dy: dy))
    }

    func keyPress(code: UInt16, flags: UInt64 = 0) {
        send(.key(code: code, down: true, flags: flags))
        send(.key(code: code, down: false, flags: flags))
    }

    // MARK: - Media Controls

    func playPause() {
        send(.media(action: .playPause))
    }

    func nextTrack() {
        send(.media(action: .nextTrack))
    }

    func previousTrack() {
        send(.media(action: .previousTrack))
    }

    func volumeUp() {
        send(.media(action: .volumeUp))
    }

    func volumeDown() {
        send(.media(action: .volumeDown))
    }

    func mute() {
        send(.media(action: .mute))
    }

    // MARK: - Brightness Controls

    func brightnessUp() {
        send(.media(action: .brightnessUp))
    }

    func brightnessDown() {
        send(.media(action: .brightnessDown))
    }

    // MARK: - System Controls

    func lockScreen() {
        send(.system(action: .lock))
    }

    @discardableResult
    func saveUnlockPairingKey(_ pairingKey: String) -> Bool {
        let saved = unlockCredentialStore.save(pairingKey: pairingKey)
        hasUnlockPairingKey = unlockCredentialStore.hasToken
        unlockStatus = saved ? nil : String(localized: "unlock_invalid_pairing_key")
        return saved
    }

    func removeUnlockPairingKey() {
        unlockCredentialStore.delete()
        hasUnlockPairingKey = false
        unlockStatus = nil
    }

    func requestUnlock() {
        guard isUnlockAvailable, let challenge = unlockChallenge else {
            unlockStatus = String(localized: "unlock_not_available")
            return
        }
        guard let token = unlockCredentialStore.token else {
            unlockStatus = String(localized: "unlock_pair_first")
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = String(localized: "cancel")
        isAuthenticatingForUnlock = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: String(localized: "unlock_auth_reason")
        ) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticatingForUnlock = false
                guard success else {
                    self.unlockStatus = error?.localizedDescription ?? String(localized: "unlock_auth_failed")
                    return
                }
                let signature = Data(HMAC<SHA256>.authenticationCode(
                    for: challenge + Data("unlock".utf8),
                    using: SymmetricKey(data: token)
                ))
                self.unlockStatus = String(localized: "unlock_sending")
                self.send(.unlock(signature: signature))
            }
        }
    }

    // MARK: - App Launcher

    func requestAppList() {
        DispatchQueue.main.async {
            self.isLoadingApps = true
        }
        send(.requestAppList)
    }

    func launchApp(bundleId: String) {
        send(.launchApp(bundleId: bundleId))
    }

    // MARK: - Screen Streaming

    func startScreenStream(quality: RemoteMessage.StreamQuality = .medium) {
        send(.startScreenStream(quality: quality))
    }

    func stopScreenStream() {
        send(.stopScreenStream)
    }

    // MARK: - Receiving

    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                self.startReceiving()
                return
            }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            print("[Client] Expecting message of \(length) bytes")

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] messageData, _, _, error in
                guard let self = self else { return }

                if let error = error {
                    print("[Client] Receive error: \(error)")
                }

                if let data = messageData {
                    print("[Client] Received \(data.count) bytes")
                    do {
                        let message = try MessageFrame.decode(data, as: ServerMessage.self)
                        DispatchQueue.main.async {
                            self.handleMessage(message)
                        }
                    } catch {
                        print("[Client] Decode error: \(error)")
                    }
                } else {
                    print("[Client] No data received")
                }

                self.startReceiving()
            }
        }
    }

    private func handleMessage(_ message: ServerMessage) {
        switch message {
        case .connected(let width, let height, let challenge, let unlockAvailable):
            screenSize = CGSize(width: width, height: height)
            unlockChallenge = challenge
            isUnlockAvailable = unlockAvailable
            print("[Client] Screen size: \(screenSize)")

        case .pong:
            print("[Client] Pong received")

        case .error(let message):
            connectionError = message

        case .appList(let appList):
            print("[Client] Processing app list with \(appList.count) apps")
            apps = appList
            isLoadingApps = false
            print("[Client] App list loaded successfully")

        case .screenFrame(let frame):
            onScreenFrameReceived?(frame)

        case .screenStreamStarted:
            isScreenStreaming = true
            print("[Client] Screen streaming started")

        case .screenStreamStopped:
            isScreenStreaming = false
            print("[Client] Screen streaming stopped")

        case .unlockResult(let success, let message):
            unlockStatus = success ? String(localized: "unlock_command_sent") : message

        case .unlockChallenge(let challenge):
            unlockChallenge = challenge
        }
    }
}
