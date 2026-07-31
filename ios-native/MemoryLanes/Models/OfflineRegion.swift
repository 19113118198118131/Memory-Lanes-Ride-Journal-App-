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

    func intersection(with other: OfflineRegionBounds) -> OfflineRegionBounds? {
        let overlap = OfflineRegionBounds(
            south: max(south, other.south),
            west: max(west, other.west),
            north: min(north, other.north),
            east: min(east, other.east)
        )
        return overlap.isValid ? overlap : nil
    }

    static func centered(at coordinate: Coordinate, sideKilometers: Double) -> OfflineRegionBounds {
        let halfSide = max(sideKilometers, 1) / 2
        let north = coordinate.projected(distanceKm: halfSide, bearingDegrees: 0)
        let east = coordinate.projected(distanceKm: halfSide, bearingDegrees: 90)
        let south = coordinate.projected(distanceKm: halfSide, bearingDegrees: 180)
        let west = coordinate.projected(distanceKm: halfSide, bearingDegrees: 270)
        return OfflineRegionBounds(
            south: max(south.latitude, -90),
            west: max(west.longitude, -180),
            north: min(north.latitude, 90),
            east: min(east.longitude, 180)
        )
    }

    func coverageFraction(by coverage: [OfflineRegionBounds]) -> Double {
        let intersections = coverage.compactMap { intersection(with: $0) }
        guard !intersections.isEmpty else { return 0 }

        let longitudeBreaks = Set(
            [west, east] + intersections.flatMap { [$0.west, $0.east] }
        ).sorted()
        var coveredArea = 0.0
        for index in longitudeBreaks.indices.dropLast() {
            let slabWest = longitudeBreaks[index]
            let slabEast = longitudeBreaks[index + 1]
            guard slabEast > slabWest else { continue }
            let midpoint = (slabWest + slabEast) / 2
            let intervals = intersections
                .filter { $0.west <= midpoint && $0.east >= midpoint }
                .map { ($0.south, $0.north) }
                .sorted { $0.0 < $1.0 }
            guard var merged = intervals.first else { continue }
            var latitudeCoverage = 0.0
            for interval in intervals.dropFirst() {
                if interval.0 <= merged.1 {
                    merged.1 = max(merged.1, interval.1)
                } else {
                    latitudeCoverage += merged.1 - merged.0
                    merged = interval
                }
            }
            latitudeCoverage += merged.1 - merged.0
            coveredArea += (slabEast - slabWest) * latitudeCoverage
        }

        let selectedArea = (east - west) * (north - south)
        guard selectedArea > 0 else { return 0 }
        return min(max(coveredArea / selectedArea, 0), 1)
    }
}

enum OfflineAreaSize: String, CaseIterable, Hashable, Sendable {
    case nearby
    case dayRide
    case touring

    var title: String {
        switch self {
        case .nearby: "25 km"
        case .dayRide: "60 km"
        case .touring: "120 km"
        }
    }

    var sideKilometers: Double {
        switch self {
        case .nearby: 25
        case .dayRide: 60
        case .touring: 120
        }
    }

    var detail: String {
        switch self {
        case .nearby: "Local roads and short escapes"
        case .dayRide: "A broad day-ride area"
        case .touring: "Long-distance coverage"
        }
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
    case deflateJSON = "deflate-json"
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

struct InstalledOfflineRoadGraph: Hashable, Sendable {
    let regionID: String
    let regionName: String
    let version: Int
    let fileURL: URL
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
