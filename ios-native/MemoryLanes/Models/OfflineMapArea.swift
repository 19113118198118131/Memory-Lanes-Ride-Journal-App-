import Foundation

struct OfflineMapArea: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let bounds: OfflineRegionBounds
    let createdAt: Date
    let minimumZoom: Double
    let maximumZoom: Double
    let bytesDownloaded: Int64
    let progress: Double
    let status: OfflineMapAreaStatus

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
    }

    var progressText: String {
        switch status {
        case .complete:
            "Ready offline"
        case .downloading:
            "Downloading \(Int((progress * 100).rounded()))%"
        case .paused:
            "Download paused"
        case .preparing:
            "Preparing download"
        case .failed:
            "Download needs attention"
        }
    }
}

enum OfflineMapAreaStatus: Equatable, Sendable {
    case preparing
    case downloading
    case paused
    case complete
    case failed
}

struct OfflineMapDownloadProgress: Equatable, Sendable {
    let fractionCompleted: Double
    let bytesCompleted: Int64

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytesCompleted, countStyle: .file)
    }
}

struct OfflineMapAreaDraft: Equatable, Sendable {
    let bounds: OfflineRegionBounds
    let minimumZoom: Double
    let maximumZoom: Double

    init(bounds: OfflineRegionBounds, minimumZoom: Double = 7, maximumZoom: Double = 15) {
        self.bounds = bounds
        self.minimumZoom = minimumZoom
        self.maximumZoom = maximumZoom
    }

    var estimatedByteCount: Int64 {
        let tiles = (Int(minimumZoom.rounded(.up))...Int(maximumZoom.rounded(.down)))
            .reduce(0) { partial, zoom in
                partial + tileCount(at: zoom)
            }
        let vectorTileEstimate = Int64(tiles) * 18_000
        return max(vectorTileEstimate + 2_000_000, 2_000_000)
    }

    var estimatedSizeText: String {
        ByteCountFormatter.string(fromByteCount: estimatedByteCount, countStyle: .file)
    }

    private func tileCount(at zoom: Int) -> Int {
        let scale = pow(2, Double(zoom))
        let westX = floor((bounds.west + 180) / 360 * scale)
        let eastX = floor((bounds.east + 180) / 360 * scale)
        let northY = floor(mercatorY(latitude: bounds.north, scale: scale))
        let southY = floor(mercatorY(latitude: bounds.south, scale: scale))
        let width = max(Int(eastX - westX) + 1, 1)
        let height = max(Int(southY - northY) + 1, 1)
        return width * height
    }

    private func mercatorY(latitude: Double, scale: Double) -> Double {
        let clamped = min(max(latitude, -85.051_128_78), 85.051_128_78)
        let radians = clamped * .pi / 180
        return (1 - asinh(tan(radians)) / .pi) / 2 * scale
    }
}

enum OfflineMapError: LocalizedError, Equatable {
    case invalidStyleURL
    case invalidSelection
    case packUnavailable
    case metadataUnavailable
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidStyleURL:
            "The offline map style is not configured."
        case .invalidSelection:
            "Choose a valid map area before downloading."
        case .packUnavailable:
            "The downloaded map could not be found."
        case .metadataUnavailable:
            "The downloaded map details could not be read."
        case .downloadFailed(let message):
            "The map download failed. \(message)"
        }
    }
}
