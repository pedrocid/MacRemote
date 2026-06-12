import Foundation
import Network

/// TCP Server that listens for connections and handles remote control messages
final class NetworkServer {

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.macremote.server", qos: .userInteractive)

    var onClientConnected: ((NWConnection) -> Void)?
    var onClientDisconnected: ((NWConnection) -> Void)?
    var onMessageReceived: ((RemoteMessage, NWConnection) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isRunning = false
    private(set) var port: UInt16 = 0

    // MARK: - Server Lifecycle

    func start(port: UInt16 = NetworkConstants.defaultPort) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        listener = try NWListener(using: parameters, on: nwPort)

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let actualPort = self?.listener?.port?.rawValue {
                    self?.port = actualPort
                    self?.isRunning = true
                    print("[Server] Listening on port \(actualPort)")
                }
            case .failed(let error):
                self?.isRunning = false
                self?.onError?(error)
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    func send(_ message: ServerMessage, to connection: NWConnection) {
        do {
            let data = try MessageFrame.encode(message)
            print("[Server] Sending \(data.count) bytes")
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("[Server] Send error: \(error)")
                } else {
                    print("[Server] Send completed successfully")
                }
            })
        } catch {
            print("[Server] Encode error: \(error)")
        }
    }

    func broadcast(_ message: ServerMessage) {
        connections.forEach { send(message, to: $0) }
    }

    func sendToConnections(_ message: ServerMessage, matching predicate: (NWConnection) -> Bool) {
        connections.filter(predicate).forEach { send(message, to: $0) }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        print("[Server] New connection from \(connection.endpoint)")
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection = connection else { return }

            switch state {
            case .ready:
                print("[Server] Client connected: \(connection.endpoint)")
                DispatchQueue.main.async {
                    self?.onClientConnected?(connection)
                }
                self?.receiveMessage(from: connection)

            case .failed(let error):
                print("[Server] Connection failed: \(error)")
                self?.removeConnection(connection)

            case .cancelled:
                print("[Server] Connection cancelled")
                self?.removeConnection(connection)

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        DispatchQueue.main.async { [weak self] in
            self?.onClientDisconnected?(connection)
        }
    }

    private func receiveMessage(from connection: NWConnection) {
        // First read 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[Server] Receive error: \(error)")
                return
            }

            if isComplete {
                self.removeConnection(connection)
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                self.receiveMessage(from: connection)
                return
            }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Now read the actual message
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] messageData, _, _, error in
                guard let self = self else { return }

                if let error = error {
                    print("[Server] Receive message error: \(error)")
                    return
                }

                if let data = messageData {
                    do {
                        let message = try MessageFrame.decode(data, as: RemoteMessage.self)
                        DispatchQueue.main.async {
                            self.onMessageReceived?(message, connection)
                        }
                    } catch {
                        print("[Server] Decode error: \(error)")
                    }
                }

                // Continue receiving
                self.receiveMessage(from: connection)
            }
        }
    }

    var connectedClientsCount: Int {
        connections.count
    }
}
