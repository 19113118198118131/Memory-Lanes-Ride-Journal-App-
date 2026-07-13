import Foundation

// MARK: - Domain models
//
// Plain value types, `Sendable` so they cross actor boundaries safely (GPX
// parsing runs on a background actor). No UI, no persistence concerns here.

/// A single recorded ride.
struct Ride: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var date: Date
    /// Distance in metres (formatting is a view concern).
    var distanceMeters: Double
    /// Moving duration in seconds.
    var durationSeconds: TimeInterval
    /// Total ascent in metres.
    var elevationGainMeters: Double
    /// Ride Coach flow score, 0–100, if analysed.
    var flowScore: Int?
    /// Where the ride was recorded, for the card label.
    var locationName: String?
    /// Source of the track.
    var source: RideSource
    /// The route polyline, decimated for map thumbnails.
    var routePreview: [Coordinate]

    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        elevationGainMeters: Double,
        flowScore: Int? = nil,
        locationName: String? = nil,
        source: RideSource = .gpx,
        routePreview: [Coordinate] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.elevationGainMeters = elevationGainMeters
        self.flowScore = flowScore
        self.locationName = locationName
        self.source = source
        self.routePreview = routePreview
    }

    // Hashable/Equatable by id — coordinates aren't Hashable and identity is enough.
    static func == (lhs: Ride, rhs: Ride) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum RideSource: String, Sendable {
    case gpx = "GPX"
    case strava = "Strava"
    case live = "Live"

    /// SF Symbol representing the source, for the card badge.
    var symbol: String {
        switch self {
        case .gpx: "doc.badge.gearshape"
        case .strava: "bolt.horizontal.fill"
        case .live: "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Formatting
//
// Centralised so "12.4 km" looks identical everywhere it appears.

extension Ride {
    var distanceFormatted: String {
        let km = distanceMeters / 1000
        return String(format: "%.1f", km)
    }

    var durationFormatted: String {
        let total = Int(durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var elevationFormatted: String {
        String(format: "%.0f", elevationGainMeters)
    }

    var dateFormatted: String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var relativeDate: String {
        date.formatted(.relative(presentation: .named))
    }
}
