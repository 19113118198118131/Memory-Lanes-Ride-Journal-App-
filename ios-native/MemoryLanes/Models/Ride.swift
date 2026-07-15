import Foundation

// MARK: - Domain models
//
// Plain value types, `Sendable` so they cross actor boundaries safely (GPX
// parsing runs on a background actor). No UI, no persistence concerns here.

/// A single recorded ride.
struct Ride: Codable, Identifiable, Hashable, Sendable {
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
    /// Persisted technique axes and safety-first Rider Craft detector summary.
    var coachScores: [String: Double]
    var riderCraftSummary: RiderCraftStorageSummary?
    /// Where the ride was recorded, for the card label.
    var locationName: String?
    /// Source of the track.
    var source: RideSource
    /// The route polyline, decimated for map thumbnails.
    var routePreview: [Coordinate]
    /// Supabase Storage path for the original GPX, when available.
    var gpxPath: String?
    /// Planned route followed while recording, when the ride started from Planner.
    var plannedRouteID: UUID?
    /// Public read-only sharing state for web share links.
    var isPublic: Bool
    var shareToken: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        elevationGainMeters: Double,
        flowScore: Int? = nil,
        coachScores: [String: Double] = [:],
        riderCraftSummary: RiderCraftStorageSummary? = nil,
        locationName: String? = nil,
        source: RideSource = .gpx,
        routePreview: [Coordinate] = [],
        gpxPath: String? = nil,
        plannedRouteID: UUID? = nil,
        isPublic: Bool = false,
        shareToken: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.elevationGainMeters = elevationGainMeters
        self.flowScore = flowScore
        self.coachScores = coachScores
        self.riderCraftSummary = riderCraftSummary
        self.locationName = locationName
        self.source = source
        self.routePreview = routePreview
        self.gpxPath = gpxPath
        self.plannedRouteID = plannedRouteID
        self.isPublic = isPublic
        self.shareToken = shareToken
    }

    // Hashable/Equatable by id — coordinates aren't Hashable and identity is enough.
    static func == (lhs: Ride, rhs: Ride) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum RideSource: String, Codable, Sendable {
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

    var publicShareURL: URL? {
        guard let shareToken else { return nil }
        return URL(string: "https://memory-lanes-ride-journal-app.vercel.app/index.html?share=\(shareToken.uuidString)")
    }

    var gpxFileName: String {
        let clean = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(clean.isEmpty ? "memory-lanes-ride" : clean).gpx"
    }
}
