import XCTest
@testable import MemoryLanes

final class RideMeshCodecTests: XCTestCase {
    func testPacketRoundTripPreservesEncryptedPayload() throws {
        let token = UUID()
        let codec = RideMeshCodec(shareToken: token)
        let payload = RideMeshPayload(
            senderID: UUID(),
            senderName: "Samar",
            body: "Regroup at the next safe stop.",
            signal: .regroup
        )

        let encoded = try codec.encode(try codec.makePacket(payload: payload))
        let packet = try codec.decode(encoded)

        XCTAssertEqual(try codec.open(packet), payload)
        XCTAssertNil(encoded.range(of: Data(payload.body.utf8)))
    }

    func testWrongRideCannotDecodePacket() throws {
        let source = RideMeshCodec(shareToken: UUID())
        let otherRide = RideMeshCodec(shareToken: UUID())
        let data = try source.encode(
            try source.makePacket(
                payload: RideMeshPayload(
                    senderID: UUID(),
                    senderName: "Rider",
                    body: "All good.",
                    signal: .allGood
                )
            )
        )

        XCTAssertThrowsError(try otherRide.decode(data)) { error in
            guard case RideMeshCodecError.wrongChannel = error else {
                return XCTFail("Expected wrongChannel, got \(error)")
            }
        }
    }

    func testRelayDecrementsTTLWithoutBreakingAuthentication() throws {
        let codec = RideMeshCodec(shareToken: UUID())
        let payload = RideMeshPayload(
            senderID: UUID(),
            senderName: "Rider",
            body: "Fuel stop requested.",
            signal: .fuelStop
        )
        let packet = try codec.makePacket(payload: payload, ttl: 2)
        let relayed = try XCTUnwrap(codec.relayed(packet))

        XCTAssertEqual(relayed.originTTL, 2)
        XCTAssertEqual(relayed.remainingTTL, 1)
        XCTAssertEqual(try codec.open(relayed), payload)
    }

    func testExpiredAndOversizedPacketsAreRejected() throws {
        let codec = RideMeshCodec(shareToken: UUID())
        let oldPacket = try codec.makePacket(
            payload: RideMeshPayload(
                senderID: UUID(),
                senderName: "Rider",
                body: "Old message",
                signal: nil
            ),
            createdAt: Date().addingTimeInterval(-21_601)
        )

        XCTAssertThrowsError(try codec.decode(try codec.encode(oldPacket)))
        XCTAssertThrowsError(
            try codec.decode(Data(repeating: 0, count: RideMeshCodec.maximumPacketByteCount + 1))
        )
    }

    func testDeduplicatorRejectsRepeatsAndEvictsOldestAtCapacity() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let now = Date()
        var deduplicator = RideMeshDeduplicator(capacity: 2)

        XCTAssertTrue(deduplicator.admit(first, at: now))
        XCTAssertFalse(deduplicator.admit(first, at: now))
        XCTAssertTrue(deduplicator.admit(second, at: now.addingTimeInterval(1)))
        XCTAssertTrue(deduplicator.admit(third, at: now.addingTimeInterval(2)))
        XCTAssertTrue(deduplicator.admit(first, at: now.addingTimeInterval(3)))
    }
}

@MainActor
final class RideMeshSessionTests: XCTestCase {
    func testQueuedMessageFlushesWhenARiderConnects() throws {
        let transport = FakeRideMeshTransport()
        let session = RideMeshSession(
            shareToken: UUID(),
            senderName: "Samar",
            transport: transport
        )
        session.start()
        session.draft = "See you at the next stop."

        session.sendDraft()

        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages.first?.deliveryState, .queued)
        XCTAssertTrue(transport.sentPackets.isEmpty)

        transport.connect(peerCount: 2)

        XCTAssertEqual(transport.sentPackets.count, 1)
        XCTAssertEqual(session.messages.first?.deliveryState, .sharedNearby(peerCount: 2))
    }

    func testIncomingMessageIsDisplayedOnceAndRelayedAwayFromIngressPeer() throws {
        let token = UUID()
        let transport = FakeRideMeshTransport()
        let session = RideMeshSession(
            shareToken: token,
            senderName: "Samar",
            transport: transport
        )
        session.start()
        transport.connect(peerCount: 2)

        let codec = RideMeshCodec(shareToken: token)
        let packet = try codec.makePacket(
            payload: RideMeshPayload(
                senderID: UUID(),
                senderName: "Alex",
                body: "Let's regroup.",
                signal: .regroup
            )
        )
        let data = try codec.encode(packet)

        transport.receive(data, from: "peer-a")
        transport.receive(data, from: "peer-a")

        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages.first?.senderName, "Alex")
        XCTAssertEqual(transport.sentPackets.count, 1)
        XCTAssertEqual(transport.sentPackets.first?.excludedPeerName, "peer-a")
    }
}

@MainActor
private final class FakeRideMeshTransport: RideMeshTransporting {
    struct SentPacket {
        let data: Data
        let excludedPeerName: String?
    }

    weak var delegate: (any RideMeshTransportDelegate)?
    private(set) var connectedPeerCount = 0
    private(set) var sentPackets: [SentPacket] = []
    private var isStarted = false

    func start(channelID: String) {
        isStarted = true
        delegate?.rideMeshTransport(self, didUpdatePeerCount: connectedPeerCount)
    }

    func stop() {
        isStarted = false
        connectedPeerCount = 0
        delegate?.rideMeshTransport(self, didUpdatePeerCount: 0)
    }

    func send(_ data: Data, excludingPeerNamed excludedPeerName: String?) -> Int {
        guard isStarted, connectedPeerCount > 0 else { return 0 }
        sentPackets.append(SentPacket(data: data, excludedPeerName: excludedPeerName))
        return max(connectedPeerCount - (excludedPeerName == nil ? 0 : 1), 0)
    }

    func connect(peerCount: Int) {
        connectedPeerCount = peerCount
        delegate?.rideMeshTransport(self, didUpdatePeerCount: peerCount)
    }

    func receive(_ data: Data, from peerName: String) {
        delegate?.rideMeshTransport(self, didReceive: data, from: peerName)
    }
}
