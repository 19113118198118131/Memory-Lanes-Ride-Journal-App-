import Foundation

struct OfflineRoadGraphArchive: Codable, Sendable {
    let formatVersion: Int
    let regionID: String
    let generatedAt: Date
    let bounds: OfflineRegionBounds
    let attribution: String
    let nodes: [OfflineRoadNode]
    let edges: [OfflineRoadEdge]
    let turnRestrictions: [OfflineTurnRestriction]
}

struct OfflineRoadNode: Codable, Hashable, Sendable {
    let id: UInt64
    let coordinate: Coordinate
}

struct OfflineRoadEdge: Codable, Hashable, Sendable {
    let wayID: UInt64
    let sourceNodeID: UInt64
    let destinationNodeID: UInt64
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let roadClass: OfflineRoadClass
    let name: String?
    let surface: String?
    let maximumSpeedKPH: Double?
}

struct OfflineTurnRestriction: Codable, Hashable, Sendable {
    let fromWayID: UInt64
    let viaNodeID: UInt64?
    let viaWayIDs: [UInt64]
    let toWayID: UInt64
    let kind: OfflineTurnRestrictionKind
    let sourceTag: String
    let condition: String?
}

enum OfflineTurnRestrictionKind: String, Codable, Sendable {
    case prohibited
    case only
}

enum OfflineRoadClass: String, Codable, Sendable {
    case motorway
    case trunk
    case primary
    case secondary
    case tertiary
    case residential
    case unclassified
    case service
}
