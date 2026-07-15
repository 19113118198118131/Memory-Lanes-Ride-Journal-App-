import Foundation

protocol OfflineRoadGraphLoading: Sendable {
    func graph(at url: URL) async throws -> OfflineRoadGraphIndex
}

actor OfflineRoadGraphLoader: OfflineRoadGraphLoading {
    static let shared = OfflineRoadGraphLoader()

    private struct CacheEntry {
        let fileSize: Int64
        let modifiedAt: Date?
        let graph: OfflineRoadGraphIndex
    }

    private let fileManager: FileManager
    private var cache: [URL: CacheEntry] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func graph(at url: URL) async throws -> OfflineRoadGraphIndex {
        try Task.checkCancellation()
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date
        if let cached = cache[url], cached.fileSize == fileSize, cached.modifiedAt == modifiedAt {
            return cached.graph
        }

        let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
        let inflated: NSData
        do {
            // Foundation names its raw DEFLATE codec `.zlib`; the release compiler matches these bytes.
            inflated = try (compressed as NSData).decompressed(using: .zlib)
        } catch {
            throw OfflineRoadRoutingError.invalidArchive
        }
        let archive: OfflineRoadGraphArchive
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            archive = try decoder.decode(OfflineRoadGraphArchive.self, from: inflated as Data)
        } catch {
            throw OfflineRoadRoutingError.invalidArchive
        }
        let graph = try OfflineRoadGraphIndex(archive: archive)
        cache[url] = CacheEntry(fileSize: fileSize, modifiedAt: modifiedAt, graph: graph)
        return graph
    }
}

struct OfflineRoadGraphIndex: Sendable {
    private static let spatialCellDegrees = 0.02

    let archive: OfflineRoadGraphArchive
    let coordinates: [UInt64: Coordinate]
    let outgoingEdges: [UInt64: [OfflineRoadEdge]]
    let nodeRestrictions: [UInt64: [OfflineTurnRestriction]]
    let wayRestrictions: [UInt64: [OfflineTurnRestriction]]
    let maximumWayHistoryCount: Int
    let weakComponentIDByNodeID: [UInt64: UInt64]
    private let spatialCells: [OfflineRoadSpatialCell: [UInt64]]

    init(archive: OfflineRoadGraphArchive) throws {
        guard archive.formatVersion == OfflineRegionStore.supportedGraphFormatVersion,
              !archive.regionID.isEmpty,
              archive.bounds.isValid,
              !archive.nodes.isEmpty,
              !archive.edges.isEmpty else {
            throw OfflineRoadRoutingError.invalidArchive
        }

        var coordinates: [UInt64: Coordinate] = [:]
        var spatialCells: [OfflineRoadSpatialCell: [UInt64]] = [:]
        for node in archive.nodes {
            guard node.id > 0,
                  coordinates[node.id] == nil,
                  node.coordinate.latitude.isFinite,
                  node.coordinate.longitude.isFinite,
                  (-90...90).contains(node.coordinate.latitude),
                  (-180...180).contains(node.coordinate.longitude) else {
                throw OfflineRoadRoutingError.invalidArchive
            }
            coordinates[node.id] = node.coordinate
            spatialCells[Self.cell(for: node.coordinate), default: []].append(node.id)
        }

        var outgoingEdges: [UInt64: [OfflineRoadEdge]] = [:]
        var wayIDs = Set<UInt64>()
        var weakComponents = OfflineRoadDisjointSet(nodeIDs: Array(coordinates.keys))
        for edge in archive.edges {
            guard edge.wayID > 0,
                  coordinates[edge.sourceNodeID] != nil,
                  coordinates[edge.destinationNodeID] != nil,
                  edge.sourceNodeID != edge.destinationNodeID,
                  edge.distanceMeters.isFinite,
                  edge.expectedTravelTime.isFinite,
                  edge.distanceMeters > 0,
                  edge.expectedTravelTime > 0 else {
                throw OfflineRoadRoutingError.invalidArchive
            }
            outgoingEdges[edge.sourceNodeID, default: []].append(edge)
            wayIDs.insert(edge.wayID)
            weakComponents.union(edge.sourceNodeID, edge.destinationNodeID)
        }
        for nodeID in outgoingEdges.keys {
            outgoingEdges[nodeID]?.sort {
                ($0.destinationNodeID, $0.wayID) < ($1.destinationNodeID, $1.wayID)
            }
        }

        var nodeRestrictions: [UInt64: [OfflineTurnRestriction]] = [:]
        var wayRestrictions: [UInt64: [OfflineTurnRestriction]] = [:]
        var maximumWayHistoryCount = 1
        for restriction in archive.turnRestrictions {
            guard wayIDs.contains(restriction.fromWayID),
                  wayIDs.contains(restriction.toWayID),
                  restriction.viaWayIDs.allSatisfy(wayIDs.contains),
                  restriction.viaNodeID.map({ coordinates[$0] != nil }) ?? true,
                  restriction.viaNodeID != nil || !restriction.viaWayIDs.isEmpty else {
                throw OfflineRoadRoutingError.invalidArchive
            }
            if let viaNodeID = restriction.viaNodeID {
                nodeRestrictions[viaNodeID, default: []].append(restriction)
            }
            if let finalViaWay = restriction.viaWayIDs.last {
                wayRestrictions[finalViaWay, default: []].append(restriction)
                maximumWayHistoryCount = max(maximumWayHistoryCount, restriction.viaWayIDs.count + 1)
            }
        }

        self.archive = archive
        self.coordinates = coordinates
        self.outgoingEdges = outgoingEdges
        self.nodeRestrictions = nodeRestrictions
        self.wayRestrictions = wayRestrictions
        self.maximumWayHistoryCount = maximumWayHistoryCount
        self.weakComponentIDByNodeID = Dictionary(
            uniqueKeysWithValues: coordinates.keys.map { ($0, weakComponents.root(of: $0)) }
        )
        self.spatialCells = spatialCells
    }

    func nearestNode(to coordinate: Coordinate, maximumDistanceMeters: Double = 5_000) -> OfflineRoadSnap? {
        return nearestNodesByWeakComponent(
            to: coordinate,
            maximumDistanceMeters: maximumDistanceMeters
        )
        .values
        .min { $0.distanceMeters < $1.distanceMeters }
    }

    func nearestNodesByWeakComponent(
        to coordinate: Coordinate,
        maximumDistanceMeters: Double = 5_000
    ) -> [UInt64: OfflineRoadSnap] {
        guard maximumDistanceMeters > 0 else { return [:] }
        let center = Self.cell(for: coordinate)
        let maximumRing = max(Int(ceil(maximumDistanceMeters / 1_500)), 1) + 1
        var candidateIDs = Set<UInt64>()
        for latitudeOffset in -maximumRing...maximumRing {
            for longitudeOffset in -maximumRing...maximumRing {
                let cell = OfflineRoadSpatialCell(
                    latitudeIndex: center.latitudeIndex + latitudeOffset,
                    longitudeIndex: center.longitudeIndex + longitudeOffset
                )
                candidateIDs.formUnion(spatialCells[cell] ?? [])
            }
        }

        var nearestByComponent: [UInt64: OfflineRoadSnap] = [:]
        for nodeID in candidateIDs {
            guard let nodeCoordinate = coordinates[nodeID],
                  let componentID = weakComponentIDByNodeID[nodeID] else { continue }
            let distance = OfflineRoadGeometry.distanceMeters(coordinate, nodeCoordinate)
            if distance <= maximumDistanceMeters {
                let snap = OfflineRoadSnap(nodeID: nodeID, coordinate: nodeCoordinate, distanceMeters: distance)
                if nearestByComponent[componentID].map({ distance < $0.distanceMeters }) ?? true {
                    nearestByComponent[componentID] = snap
                }
            }
        }
        return nearestByComponent
    }

    private static func cell(for coordinate: Coordinate) -> OfflineRoadSpatialCell {
        OfflineRoadSpatialCell(
            latitudeIndex: Int(floor((coordinate.latitude + 90) / spatialCellDegrees)),
            longitudeIndex: Int(floor((coordinate.longitude + 180) / spatialCellDegrees))
        )
    }
}

private struct OfflineRoadDisjointSet {
    private var parent: [UInt64: UInt64]
    private var size: [UInt64: Int]

    init(nodeIDs: [UInt64]) {
        parent = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, $0) })
        size = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, 1) })
    }

    mutating func root(of nodeID: UInt64) -> UInt64 {
        guard let directParent = parent[nodeID] else { return nodeID }
        if directParent == nodeID { return nodeID }
        let value = root(of: directParent)
        parent[nodeID] = value
        return value
    }

    mutating func union(_ first: UInt64, _ second: UInt64) {
        var firstRoot = root(of: first)
        var secondRoot = root(of: second)
        guard firstRoot != secondRoot else { return }
        if size[firstRoot, default: 1] < size[secondRoot, default: 1] {
            swap(&firstRoot, &secondRoot)
        }
        parent[secondRoot] = firstRoot
        size[firstRoot, default: 1] += size[secondRoot, default: 1]
    }
}

struct OfflineRoadSnap: Equatable, Sendable {
    let nodeID: UInt64
    let coordinate: Coordinate
    let distanceMeters: Double
}

private struct OfflineRoadSpatialCell: Hashable, Sendable {
    let latitudeIndex: Int
    let longitudeIndex: Int
}

enum OfflineRoadRoutingError: LocalizedError, Equatable, Sendable {
    case noCoverage
    case invalidArchive
    case cannotSnap
    case noPath
    case searchLimitReached

    var errorDescription: String? {
        switch self {
        case .noCoverage:
            "No downloaded road graph covers this route."
        case .invalidArchive:
            "The downloaded road graph is invalid and could not be used."
        case .cannotSnap:
            "A route point could not be matched to a downloaded road."
        case .noPath:
            "The downloaded roads do not contain a connected route between these points."
        case .searchLimitReached:
            "This offline route is too complex to calculate on this device."
        }
    }
}

enum OfflineRoadGeometry {
    static func distanceMeters(_ first: Coordinate, _ second: Coordinate) -> Double {
        let latitude1 = first.latitude * .pi / 180
        let latitude2 = second.latitude * .pi / 180
        let latitudeDelta = latitude2 - latitude1
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371_008.8 * 2 * atan2(sqrt(value), sqrt(max(1 - value, 0)))
    }
}
