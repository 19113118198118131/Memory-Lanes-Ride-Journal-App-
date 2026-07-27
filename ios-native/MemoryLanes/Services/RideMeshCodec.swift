import CryptoKit
import Foundation

struct RideMeshCodec: Sendable {
    static let maximumPacketByteCount = 8 * 1024
    static let maximumMessageLength = 280
    static let defaultTTL: UInt8 = 4

    let channelID: String
    private let key: SymmetricKey

    init(shareToken: UUID) {
        let tokenData = Data(shareToken.uuidString.lowercased().utf8)
        let channelDigest = SHA256.hash(data: Data("memory-lanes-ride-mesh-channel-v1".utf8) + tokenData)
        self.channelID = Data(channelDigest.prefix(8)).map { String(format: "%02x", $0) }.joined()

        let inputKey = SymmetricKey(data: SHA256.hash(data: tokenData))
        self.key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data("memory-lanes-ride-mesh-salt-v1".utf8),
            info: Data(channelID.utf8),
            outputByteCount: 32
        )
    }

    func makePacket(
        payload: RideMeshPayload,
        messageID: UUID = UUID(),
        createdAt: Date = Date(),
        ttl: UInt8 = defaultTTL
    ) throws -> RideMeshPacket {
        let cleanBody = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty, cleanBody.count <= Self.maximumMessageLength else {
            throw RideMeshCodecError.invalidMessage
        }
        guard !payload.senderName.isEmpty, payload.senderName.count <= 40 else {
            throw RideMeshCodecError.invalidSender
        }

        let timestamp = Int64((createdAt.timeIntervalSince1970 * 1_000).rounded())
        let normalizedPayload = RideMeshPayload(
            senderID: payload.senderID,
            senderName: payload.senderName,
            body: cleanBody,
            signal: payload.signal
        )
        let payloadData = try JSONEncoder().encode(normalizedPayload)
        let sealed = try ChaChaPoly.seal(
            payloadData,
            using: key,
            authenticating: associatedData(
                messageID: messageID,
                timestamp: timestamp,
                originTTL: ttl
            )
        )
        return RideMeshPacket(
            version: RideMeshPacket.currentVersion,
            messageID: messageID,
            channelID: channelID,
            createdAtMilliseconds: timestamp,
            originTTL: ttl,
            remainingTTL: ttl,
            sealedPayload: sealed.combined
        )
    }

    func encode(_ packet: RideMeshPacket) throws -> Data {
        let data = try JSONEncoder().encode(packet)
        guard data.count <= Self.maximumPacketByteCount else {
            throw RideMeshCodecError.packetTooLarge
        }
        return data
    }

    func decode(_ data: Data, now: Date = Date()) throws -> RideMeshPacket {
        guard data.count <= Self.maximumPacketByteCount else {
            throw RideMeshCodecError.packetTooLarge
        }
        let packet = try JSONDecoder().decode(RideMeshPacket.self, from: data)
        guard packet.version == RideMeshPacket.currentVersion else {
            throw RideMeshCodecError.unsupportedVersion
        }
        guard packet.channelID == channelID else {
            throw RideMeshCodecError.wrongChannel
        }
        guard packet.originTTL <= 8, packet.remainingTTL <= packet.originTTL else {
            throw RideMeshCodecError.invalidTTL
        }
        let createdAt = Date(timeIntervalSince1970: Double(packet.createdAtMilliseconds) / 1_000)
        let age = now.timeIntervalSince(createdAt)
        guard age >= -300, age <= 21_600 else {
            throw RideMeshCodecError.expired
        }
        return packet
    }

    func open(_ packet: RideMeshPacket) throws -> RideMeshPayload {
        let box = try ChaChaPoly.SealedBox(combined: packet.sealedPayload)
        let clearData = try ChaChaPoly.open(
            box,
            using: key,
            authenticating: associatedData(
                messageID: packet.messageID,
                timestamp: packet.createdAtMilliseconds,
                originTTL: packet.originTTL
            )
        )
        let payload = try JSONDecoder().decode(RideMeshPayload.self, from: clearData)
        guard !payload.body.isEmpty, payload.body.count <= Self.maximumMessageLength else {
            throw RideMeshCodecError.invalidMessage
        }
        guard !payload.senderName.isEmpty, payload.senderName.count <= 40 else {
            throw RideMeshCodecError.invalidSender
        }
        return payload
    }

    func relayed(_ packet: RideMeshPacket) -> RideMeshPacket? {
        guard packet.remainingTTL > 0 else { return nil }
        var copy = packet
        copy.remainingTTL -= 1
        return copy
    }

    private func associatedData(
        messageID: UUID,
        timestamp: Int64,
        originTTL: UInt8
    ) -> Data {
        Data(
            "\(RideMeshPacket.currentVersion)|\(messageID.uuidString.lowercased())|\(channelID)|\(timestamp)|\(originTTL)"
                .utf8
        )
    }
}

enum RideMeshCodecError: LocalizedError {
    case invalidMessage
    case invalidSender
    case packetTooLarge
    case unsupportedVersion
    case wrongChannel
    case invalidTTL
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidMessage: "Messages must contain 1–280 characters."
        case .invalidSender: "The rider name is not valid."
        case .packetTooLarge: "This nearby message is too large."
        case .unsupportedVersion: "This nearby rider is using an incompatible Ride Mesh version."
        case .wrongChannel: "This message belongs to a different group ride."
        case .invalidTTL: "This nearby message has invalid relay information."
        case .expired: "This nearby message has expired."
        }
    }
}

struct RideMeshDeduplicator: Sendable {
    private var seen: [UUID: Date] = [:]
    private let capacity: Int
    private let lifetime: TimeInterval

    init(capacity: Int = 512, lifetime: TimeInterval = 21_600) {
        self.capacity = max(capacity, 1)
        self.lifetime = lifetime
    }

    mutating func admit(_ id: UUID, at date: Date = Date()) -> Bool {
        prune(now: date)
        guard seen[id] == nil else { return false }
        if seen.count >= capacity, let oldest = seen.min(by: { $0.value < $1.value })?.key {
            seen.removeValue(forKey: oldest)
        }
        seen[id] = date
        return true
    }

    private mutating func prune(now: Date) {
        seen = seen.filter { now.timeIntervalSince($0.value) <= lifetime }
    }
}
