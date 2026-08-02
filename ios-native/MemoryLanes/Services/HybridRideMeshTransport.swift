import Foundation

@MainActor
final class HybridRideMeshTransport: RideMeshTransporting {
    weak var delegate: (any RideMeshTransportDelegate)?

    private let transports: [any RideMeshTransporting]
    private var peerCounts: [ObjectIdentifier: Int] = [:]
    private var failedTransports: Set<ObjectIdentifier> = []
    private var isStarted = false

    var connectedPeerCount: Int {
        // The same phone is commonly visible over BLE and local Wi-Fi. Taking
        // the largest path count avoids presenting duplicate riders.
        peerCounts.values.max() ?? 0
    }

    init(
        transports: [any RideMeshTransporting] = [
            BluetoothRideMeshTransport(),
            NearbyRideMeshTransport()
        ]
    ) {
        self.transports = transports
        for transport in transports {
            transport.delegate = self
            peerCounts[ObjectIdentifier(transport)] = 0
        }
    }

    func start(channelID: String) {
        isStarted = true
        failedTransports.removeAll()
        for transport in transports {
            transport.start(channelID: channelID)
        }
        reportPeerCount()
    }

    func stop() {
        isStarted = false
        for transport in transports {
            transport.stop()
            peerCounts[ObjectIdentifier(transport)] = 0
        }
        failedTransports.removeAll()
        reportPeerCount()
    }

    @discardableResult
    func send(_ data: Data, excludingPeerNamed excludedPeerName: String?) -> Int {
        var largestRecipientCount = 0
        for transport in transports {
            let id = ObjectIdentifier(transport)
            let prefix = transportPrefix(for: id)
            let exclusion: String?
            if let excludedPeerName,
               excludedPeerName.hasPrefix(prefix) {
                exclusion = String(excludedPeerName.dropFirst(prefix.count))
            } else {
                exclusion = nil
            }
            largestRecipientCount = max(
                largestRecipientCount,
                transport.send(data, excludingPeerNamed: exclusion)
            )
        }
        return largestRecipientCount
    }

    private func reportPeerCount() {
        delegate?.rideMeshTransport(
            self,
            didUpdatePeerCount: isStarted ? connectedPeerCount : 0
        )
    }

    private func transportPrefix(for id: ObjectIdentifier) -> String {
        "\(id.hashValue):"
    }
}

extension HybridRideMeshTransport: RideMeshTransportDelegate {
    func rideMeshTransport(
        _ transport: any RideMeshTransporting,
        didReceive data: Data,
        from peerName: String
    ) {
        let prefix = transportPrefix(for: ObjectIdentifier(transport))
        delegate?.rideMeshTransport(self, didReceive: data, from: prefix + peerName)
    }

    func rideMeshTransport(
        _ transport: any RideMeshTransporting,
        didUpdatePeerCount peerCount: Int
    ) {
        let id = ObjectIdentifier(transport)
        peerCounts[id] = peerCount
        if peerCount > 0 {
            failedTransports.remove(id)
        }
        reportPeerCount()
    }

    func rideMeshTransport(
        _ transport: any RideMeshTransporting,
        didFail message: String
    ) {
        let id = ObjectIdentifier(transport)
        failedTransports.insert(id)
        peerCounts[id] = 0
        reportPeerCount()
        guard failedTransports.count == transports.count else { return }
        delegate?.rideMeshTransport(self, didFail: message)
    }
}
