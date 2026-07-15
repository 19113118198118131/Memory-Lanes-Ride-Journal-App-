import Foundation

struct OfflineRegionBounds: Codable, Hashable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    var isValid: Bool {
        (-90...90).contains(south)
            && (-90...90).contains(north)
            && (-180...180).contains(west)
            && (-180...180).contains(east)
            && south < north
            && west < east
    }

    var center: Coordinate {
        Coordinate(
            latitude: (south + north) / 2,
            longitude: (west + east) / 2
        )
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        (south...north).contains(coordinate.latitude)
            && (west...east).contains(coordinate.longitude)
    }

    func intersects(_ other: OfflineRegionBounds) -> Bool {
        south <= other.north
            && north >= other.south
            && west <= other.east
            && east >= other.west
    }
}

struct OfflineRegionDescriptor: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let bounds: OfflineRegionBounds
    let version: Int
    let formatVersion: Int
    let encoding: OfflineRoadGraphEncoding
    let byteCount: Int64
    let sha256: String
    let downloadPath: String
    let updatedAt: Date

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

enum OfflineRoadGraphEncoding: String, Codable, Sendable {
    case gzipJSON = "gzip-json"
}

struct OfflineRegionManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let regions: [OfflineRegionDescriptor]
}

struct SignedOfflineRegionManifestEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let keyID: String
    let payload: String
    let signature: String
}

struct InstalledOfflineRegion: Codable, Hashable, Identifiable, Sendable {
    let descriptor: OfflineRegionDescriptor
    let installedAt: Date
    let localFileName: String

    var id: String { descriptor.id }

    func needsUpdate(comparedWith available: OfflineRegionDescriptor?) -> Bool {
        guard let available else { return false }
        return available.version > descriptor.version
    }
}

enum OfflineRegionInstallPhase: Equatable, Sendable {
    case downloading
    case verifying
    case activating

    var title: String {
        switch self {
        case .downloading: "Downloading roads"
        case .verifying: "Verifying download"
        case .activating: "Making area available"
        }
    }
}
