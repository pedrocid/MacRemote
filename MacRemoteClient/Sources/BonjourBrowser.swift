import Foundation
import Network

/// Discovers MacRemote servers on the local network using Bonjour
final class BonjourBrowser: ObservableObject {

    @Published var servers: [DiscoveredServer] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.macremote.browser")

    struct DiscoveredServer: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let endpoint: NWEndpoint

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
            lhs.id == rhs.id
        }
    }

    func startBrowsing() {
        stopBrowsing()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: NetworkConstants.serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.servers = results.compactMap { result in
                    switch result.endpoint {
                    case .service(let name, _, _, _):
                        return DiscoveredServer(name: name, endpoint: result.endpoint)
                    default:
                        return nil
                    }
                }
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
}
