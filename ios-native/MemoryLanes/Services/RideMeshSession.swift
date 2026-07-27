import Foundation
import Observation

@MainActor
@Observable
final class RideMeshSession: RideMeshTransportDelegate {
    private(set) var state: RideMeshConnectionState = .idle
    private(set) var messages: [RideMeshMessage] = []
    private(set) var isActive = false
    var draft = ""
    var errorMessage: String?

    private let senderID = UUID()
    private let senderName: String
    private let codec: RideMeshCodec
    private let transport: any RideMeshTransporting
    private var deduplicator = RideMeshDeduplicator()
    private var queuedPackets: [UUID: Data] = [:]

    init(
        shareToken: UUID,
        senderName: String,
        transport: any RideMeshTransporting = NearbyRideMeshTransport()
    ) {
        self.senderName = String(senderName.prefix(40))
        self.codec = RideMeshCodec(shareToken: shareToken)
        self.transport = transport
        self.transport.delegate = self
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= RideMeshCodec.maximumMessageLength
            && isActive
    }

    var peerCount: Int {
        transport.connectedPeerCount
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        errorMessage = nil
        state = .scanning
        transport.start(channelID: codec.channelID)
    }

    func stop() {
        guard isActive else { return }
        transport.stop()
        isActive = false
        state = .idle
    }

    func retry() {
        stop()
        start()
    }

    func sendDraft() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        send(body: body, signal: nil)
    }

    func send(signal: RideMeshSignal) {
        send(body: signal.message, signal: signal)
    }

    private func send(body: String, signal: RideMeshSignal?) {
        guard isActive else { return }
        errorMessage = nil
        let messageID = UUID()
        let createdAt = Date()

        do {
            let packet = try codec.makePacket(
                payload: RideMeshPayload(
                    senderID: senderID,
                    senderName: senderName,
                    body: body,
                    signal: signal
                ),
                messageID: messageID,
                createdAt: createdAt
            )
            let data = try codec.encode(packet)
            _ = deduplicator.admit(messageID, at: createdAt)
            let recipientCount = transport.send(data, excludingPeerNamed: nil)
            if recipientCount == 0 {
                queuedPackets[messageID] = data
            }
            append(
                RideMeshMessage(
                    id: messageID,
                    senderID: senderID,
                    senderName: senderName,
                    body: body,
                    signal: signal,
                    createdAt: createdAt,
                    isMine: true,
                    deliveryState: recipientCount == 0
                        ? .queued
                        : .sharedNearby(peerCount: recipientCount)
                )
            )
            Haptics.selection()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    func rideMeshTransport(
        _ transport: any RideMeshTransporting,
        didReceive data: Data,
        from peerName: String
    ) {
        do {
            let packet = try codec.decode(data)
            guard deduplicator.admit(packet.messageID) else { return }
            let payload = try codec.open(packet)
            if payload.senderID != senderID {
                append(
                    RideMeshMessage(
                        id: packet.messageID,
                        senderID: payload.senderID,
                        senderName: payload.senderName,
                        body: payload.body,
                        signal: payload.signal,
                        createdAt: Date(
                            timeIntervalSince1970: Double(packet.createdAtMilliseconds) / 1_000
                        ),
                        isMine: false,
                        deliveryState: nil
                    )
                )
                Haptics.selection()
            }
            if let relay = codec.relayed(packet),
               let relayData = try? codec.encode(relay) {
                _ = transport.send(relayData, excludingPeerNamed: peerName)
            }
        } catch {
            // Foreign, expired, tampered, and wrong-ride packets are expected
            // on a shared radio and intentionally do not interrupt the rider.
        }
    }

    func rideMeshTransport(
        _ transport: any RideMeshTransporting,
        didUpdatePeerCount peerCount: Int
    ) {
        guard isActive else {
            state = .idle
            return
        }
        state = peerCount > 0 ? .connected(peerCount: peerCount) : .scanning
        if peerCount > 0 {
            flushQueuedPackets()
        }
    }

    func rideMeshTransport(
        _ transport: any RideMeshTransporting,
        didFail message: String
    ) {
        errorMessage = message
        state = .unavailable(message: message)
    }

    private func flushQueuedPackets() {
        for (messageID, data) in Array(queuedPackets) {
            let recipientCount = transport.send(data, excludingPeerNamed: nil)
            guard recipientCount > 0 else { continue }
            queuedPackets.removeValue(forKey: messageID)
            updateDelivery(messageID: messageID, state: .sharedNearby(peerCount: recipientCount))
        }
    }

    private func append(_ message: RideMeshMessage) {
        messages.append(message)
        messages.sort { $0.createdAt < $1.createdAt }
        if messages.count > 200 {
            messages.removeFirst(messages.count - 200)
        }
    }

    private func updateDelivery(messageID: UUID, state: RideMeshDeliveryState) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].deliveryState = state
    }
}
