import Foundation

struct OfflineRoadGraphArchive: Codable, Sendable {
    let formatVersion: Int
    let regionID: String
    let generatedAt: Date
    let bounds: OfflineRegionBounds
    let attribution: String
    let nodes: [OfflineRoadNode]
    let edges: [OfflineRoadEdge]
}

struct OfflineRoadNode: Codable, Hashable, Sendable {
    let id: UInt64
    let coordinate: Coordinate
}

struct OfflineRoadEdge: Codable, Hashable, Sendable {
    let sourceNodeID: UInt64
    let destinationNodeID: UInt64
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let roadClass: OfflineRoadClass
    let name: String?
    let surface: String?
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
