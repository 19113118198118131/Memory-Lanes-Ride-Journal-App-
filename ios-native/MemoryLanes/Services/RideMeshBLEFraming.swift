import Foundation

enum RideMeshBLEFrameKind: UInt8, Sendable {
    case handshake = 1
    case packet = 2
}

struct RideMeshBLEFrame: Equatable, Sendable {
    static let headerByteCount = 14
    static let maximumFragmentCount = 1_024

    let kind: RideMeshBLEFrameKind
    let transferID: UInt64
    let index: Int
    let count: Int
    let payload: Data

    func encoded() -> Data {
        var data = Data(capacity: Self.headerByteCount + payload.count)
        data.append(0xB7)
        data.append((1 << 4) | kind.rawValue)
        append(transferID, to: &data)
        append(UInt16(index), to: &data)
        append(UInt16(count), to: &data)
        data.append(payload)
        return data
    }

    static func decode(_ data: Data) -> RideMeshBLEFrame? {
        guard data.count >= headerByteCount,
              data[data.startIndex] == 0xB7 else { return nil }

        let versionAndKind = data[data.startIndex + 1]
        guard versionAndKind >> 4 == 1,
              let kind = RideMeshBLEFrameKind(rawValue: versionAndKind & 0x0F) else { return nil }

        let transferID = readUInt64(data, at: 2)
        let index = Int(readUInt16(data, at: 10))
        let count = Int(readUInt16(data, at: 12))
        guard count > 0,
              count <= maximumFragmentCount,
              index >= 0,
              index < count else { return nil }

        return RideMeshBLEFrame(
            kind: kind,
            transferID: transferID,
            index: index,
            count: count,
            payload: data.subdata(in: headerByteCount..<data.count)
        )
    }

    static func fragments(
        for data: Data,
        kind: RideMeshBLEFrameKind,
        maximumFrameByteCount: Int,
        transferID: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    ) -> [Data] {
        let payloadByteCount = max(maximumFrameByteCount - headerByteCount, 1)
        let fragmentCount = max(Int(ceil(Double(data.count) / Double(payloadByteCount))), 1)
        guard fragmentCount <= maximumFragmentCount else { return [] }

        return (0..<fragmentCount).map { index in
            let lowerBound = min(index * payloadByteCount, data.count)
            let upperBound = min(lowerBound + payloadByteCount, data.count)
            return RideMeshBLEFrame(
                kind: kind,
                transferID: transferID,
                index: index,
                count: fragmentCount,
                payload: data.subdata(in: lowerBound..<upperBound)
            ).encoded()
        }
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        (UInt16(data[data.startIndex + offset]) << 8)
            | UInt16(data[data.startIndex + offset + 1])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { partial, byteOffset in
            (partial << 8) | UInt64(data[data.startIndex + offset + byteOffset])
        }
    }
}

struct RideMeshBLEAssembly: Equatable, Sendable {
    let kind: RideMeshBLEFrameKind
    let data: Data
}

struct RideMeshBLEReassembler: Sendable {
    private struct Key: Hashable, Sendable {
        let peer: String
        let transferID: UInt64
    }

    private struct Pending: Sendable {
        let kind: RideMeshBLEFrameKind
        let count: Int
        let createdAt: Date
        var fragments: [Int: Data]
        var byteCount: Int
    }

    private var pending: [Key: Pending] = [:]
    private let maximumAssemblyByteCount: Int
    private let maximumPendingAssemblies: Int
    private let timeout: TimeInterval

    init(
        maximumAssemblyByteCount: Int = RideMeshCodec.maximumPacketByteCount,
        maximumPendingAssemblies: Int = 64,
        timeout: TimeInterval = 30
    ) {
        self.maximumAssemblyByteCount = maximumAssemblyByteCount
        self.maximumPendingAssemblies = maximumPendingAssemblies
        self.timeout = timeout
    }

    mutating func ingest(
        _ data: Data,
        from peer: String,
        now: Date = Date()
    ) -> RideMeshBLEAssembly? {
        prune(now: now)
        guard let frame = RideMeshBLEFrame.decode(data) else { return nil }
        let key = Key(peer: peer, transferID: frame.transferID)

        if pending[key] == nil {
            if pending.count >= maximumPendingAssemblies,
               let oldest = pending.min(by: { $0.value.createdAt < $1.value.createdAt })?.key {
                pending.removeValue(forKey: oldest)
            }
            pending[key] = Pending(
                kind: frame.kind,
                count: frame.count,
                createdAt: now,
                fragments: [:],
                byteCount: 0
            )
        }

        guard var assembly = pending[key],
              assembly.kind == frame.kind,
              assembly.count == frame.count else {
            pending.removeValue(forKey: key)
            return nil
        }

        if assembly.fragments[frame.index] == nil {
            assembly.fragments[frame.index] = frame.payload
            assembly.byteCount += frame.payload.count
        }
        guard assembly.byteCount <= maximumAssemblyByteCount else {
            pending.removeValue(forKey: key)
            return nil
        }
        pending[key] = assembly

        guard assembly.fragments.count == assembly.count else { return nil }
        var joined = Data(capacity: assembly.byteCount)
        for index in 0..<assembly.count {
            guard let fragment = assembly.fragments[index] else { return nil }
            joined.append(fragment)
        }
        pending.removeValue(forKey: key)
        return RideMeshBLEAssembly(kind: assembly.kind, data: joined)
    }

    private mutating func prune(now: Date) {
        pending = pending.filter { now.timeIntervalSince($0.value.createdAt) <= timeout }
    }
}
