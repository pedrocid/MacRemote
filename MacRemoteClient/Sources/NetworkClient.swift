import Foundation
import Network

/// TCP Client that connects to a MacRemote server
final class NetworkClient: ObservableObject {

    @Published var isConnected = false
    @Published var screenSize: CGSize = .zero
    @Published var connectionError: String?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.macremote.client", qos: .userInteractive)

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

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] messageData, _, _, _ in
                guard let self = self else { return }

                if let data = messageData {
                    do {
                        let message = try MessageFrame.decode(data, as: ServerMessage.self)
                        DispatchQueue.main.async {
                            self.handleMessage(message)
                        }
                    } catch {
                        print("[Client] Decode error: \(error)")
                    }
                }

                self.startReceiving()
            }
        }
    }

    private func handleMessage(_ message: ServerMessage) {
        switch message {
        case .connected(let width, let height):
            screenSize = CGSize(width: width, height: height)
            print("[Client] Screen size: \(screenSize)")

        case .pong:
            print("[Client] Pong received")

        case .error(let message):
            connectionError = message
        }
    }
}
