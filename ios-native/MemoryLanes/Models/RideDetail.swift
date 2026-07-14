import Foundation

// MARK: - RideDetail
//
// The full analysis for one ride, loaded lazily when a ride is opened. Kept
// separate from `Ride` (the list model) so the dashboard stays cheap to load —
// corner tickets, moments, weather, and the elevation profile only come down
// when a rider actually taps in.

struct RideDetail: Identifiable, Sendable {
    let id: UUID              // matches the parent Ride.id
    var routePreview: [Coordinate]
    var replayPoints: [ReplayPoint]
    var elevation: [ElevationSample]
    var corners: [CornerTicket]
    var moments: [Moment]
    var weather: Weather?
    var coachScore: Int?
    var coachScores: [RideCoachScore]
    var analytics: RideAnalytics? = nil
    var riderCraft: RiderCraftAnalysis? = nil
    var coachTrend: String? = nil
    var feedback: RideFeedback? = nil
    var plannedRoute: PlannedRoute? = nil
    var routeMatch: RouteMatchSummary? = nil
    /// The coaching debrief — one plain-English takeaway.
    var debrief: String?
}

struct RouteMatchSummary: Sendable {
    let plannedDistanceKm: Double
    let actualDistanceKm: Double
    let distanceDeltaKm: Double
    let matchedPercent: Double
    let averageDeviationMeters: Double

    var matchedText: String { String(format: "%.0f%%", matchedPercent) }
    var averageDeviationText: String { String(format: "%.0f m", averageDeviationMeters) }
    var distanceDeltaText: String {
        let sign = distanceDeltaKm >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f km", distanceDeltaKm))"
    }

    var verdict: String {
        if matchedPercent >= 85 && abs(distanceDeltaKm) <= 2 {
            return "Tightly followed"
        }
        if matchedPercent >= 65 {
            return "Mostly followed"
        }
        return "Partial match"
    }
}

struct RideCoachScore: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case cornerEntry
        case exitDrive
        case brakingFeel
        case throttleFeel
        case consistency

        var storageKey: String {
            switch self {
            case .cornerEntry: "cornerEntry"
            case .exitDrive: "exitDrive"
            case .brakingFeel: "brakingSmoothness"
            case .throttleFeel: "throttleSmoothness"
            case .consistency: "consistency"
            }
        }

        var title: String {
            switch self {
            case .cornerEntry: "Corner Entry"
            case .exitDrive: "Exit Drive"
            case .brakingFeel: "Braking Feel"
            case .throttleFeel: "Throttle Feel"
            case .consistency: "Consistency"
            }
        }

        var symbol: String {
            switch self {
            case .cornerEntry: "arrow.turn.down.right"
            case .exitDrive: "arrow.up.forward"
            case .brakingFeel: "hand.raised.fill"
            case .throttleFeel: "gauge.with.dots.needle.67percent"
            case .consistency: "repeat"
            }
        }
    }

    var id: Kind { kind }
    let kind: Kind
    let value: Int
    let caption: String
}

struct ReplayPoint: Identifiable, Hashable, Sendable {
    var id: Int { index }
    let index: Int
    let coordinate: Coordinate
    let elapsedSeconds: TimeInterval
    let distanceKm: Double
    let elevationMeters: Double
    let speedKmh: Double

    var elapsedFormatted: String {
        let total = Int(elapsedSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Ride Analytics

struct RideAnalytics: Sendable {
    var acceleration: [RideAccelerationSample]
    var brakingZones: [RideInputZone]
    var driveZones: [RideInputZone]
    var gripUsage: [GripUsagePoint]
    var cornerPoints: [CornerAnalyticsPoint]
    var composition: [RideCompositionSlice]
    var insights: [RideAnalyticsInsight]

    static let empty = RideAnalytics(
        acceleration: [],
        brakingZones: [],
        driveZones: [],
        gripUsage: [],
        cornerPoints: [],
        composition: [],
        insights: []
    )

    var hardestBrakingG: Double? {
        brakingZones.map { abs($0.peakAcceleration) / 9.81 }.max()
    }

    var brakingFeelText: String {
        guard let average = averageSmoothness(in: brakingZones) else { return "Not enough data" }
        if average >= 80 { return "Progressive" }
        if average >= 60 { return "Mostly smooth" }
        return "Needs smoothing"
    }

    private func averageSmoothness(in zones: [RideInputZone]) -> Double? {
        guard !zones.isEmpty else { return nil }
        return zones.map(\.smoothness).reduce(0, +) / Double(zones.count)
    }
}

struct RideAccelerationSample: Identifiable, Hashable, Sendable {
    let index: Int
    let distanceKm: Double
    let acceleration: Double

    var id: Int { index }
}

struct RideInputZone: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case braking
        case drive
    }

    let kind: Kind
    let startIndex: Int
    let endIndex: Int
    let startKm: Double
    let endKm: Double
    let peakAcceleration: Double
    let smoothness: Double

    var id: String { "\(kind.rawValue)-\(startIndex)-\(endIndex)" }
}

struct GripUsagePoint: Identifiable, Hashable, Sendable {
    let index: Int
    /// Signed lateral acceleration in g: left negative, right positive.
    let lateralG: Double
    /// Longitudinal acceleration in g: braking negative, drive positive.
    let longitudinalG: Double

    var id: Int { index }
}

struct CornerAnalyticsPoint: Identifiable, Hashable, Sendable {
    let replayIndex: Int
    let radiusMeters: Double
    let apexKmh: Double
    let lateralG: Double
    let leanDegrees: Double
    let sweepDegrees: Double

    var id: Int { replayIndex }
}

struct RideCompositionSlice: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case cornering = "Cornering"
        case braking = "Braking"
        case driving = "Driving"
        case cruising = "Cruising"
        case stopped = "Stopped"
    }

    let kind: Kind
    let seconds: TimeInterval

    var id: Kind { kind }
}

struct RideAnalyticsInsight: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case grip
        case corners
        case elevation
        case inputs
    }

    let kind: Kind
    let summary: String
    let detail: String

    var id: Kind { kind }
}

// MARK: - ElevationSample
//
// One point on the elevation profile. Distance is the identity so Swift Charts
// can plot and scrub it directly.

struct ElevationSample: Identifiable, Hashable, Sendable {
    var id: Double { distanceKm }
    let distanceKm: Double
    let elevationM: Double
}

// MARK: - CornerTicket
//
// One analysed corner: geometry, the three reference speeds, a verdict, a
// coaching tip, and repeat-corner recognition. Scores reward smoothness and
// technique, never speed or lean angle.

struct CornerTicket: Identifiable, Sendable {
    let id: UUID
    var index: Int
    var shape: CornerShape
    var entrySpeed: Int      // km/h
    var apexSpeed: Int
    var exitSpeed: Int
    var verdict: Verdict
    var tip: String
    /// e.g. "Ridden 4× · apex today 52 km/h, a new best" — nil for first visit.
    var repeatNote: String?
    var replayIndex: Int?
    var radiusMeters: Int?
    var sweepDegrees: Int?
    var leanDegrees: Int?
    var lateralG: Double?

    enum Verdict: String, Sendable {
        case smooth = "Smooth"
        case rushed = "Rushed entry"
        case early = "Early apex"
        case tidy = "Tidy line"

        var tint: VerdictTint {
            switch self {
            case .smooth, .tidy: .good
            case .rushed: .warn
            case .early: .info
            }
        }
    }

    enum VerdictTint: Sendable { case good, warn, info }

    init(
        id: UUID = UUID(),
        index: Int,
        shape: CornerShape,
        entrySpeed: Int,
        apexSpeed: Int,
        exitSpeed: Int,
        verdict: Verdict,
        tip: String,
        repeatNote: String? = nil,
        replayIndex: Int? = nil,
        radiusMeters: Int? = nil,
        sweepDegrees: Int? = nil,
        leanDegrees: Int? = nil,
        lateralG: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.shape = shape
        self.entrySpeed = entrySpeed
        self.apexSpeed = apexSpeed
        self.exitSpeed = exitSpeed
        self.verdict = verdict
        self.tip = tip
        self.repeatNote = repeatNote
        self.replayIndex = replayIndex
        self.radiusMeters = radiusMeters
        self.sweepDegrees = sweepDegrees
        self.leanDegrees = leanDegrees
        self.lateralG = lateralG
    }
}

/// Corner geometry, rendered as a glyph on the ticket.
enum CornerShape: String, Sendable {
    case leftHairpin = "Left hairpin"
    case rightHairpin = "Right hairpin"
    case leftSweeper = "Left sweeper"
    case rightSweeper = "Right sweeper"
    case chicane = "Chicane"

    /// SF Symbol approximating the corner's direction.
    var symbol: String {
        switch self {
        case .leftHairpin: "arrow.uturn.left"
        case .rightHairpin: "arrow.uturn.right"
        case .leftSweeper: "arrow.turn.up.left"
        case .rightSweeper: "arrow.turn.up.right"
        case .chicane: "arrow.left.arrow.right"
        }
    }
}

// MARK: - Moment
//
// A pinned point on the ride with a note — the raw material of the journal.

struct Moment: Identifiable, Sendable {
    let id: UUID
    var title: String
    var note: String
    var coordinate: Coordinate
    var routeIndex: Int?
    var speedKmh: Double?
    var elevationMeters: Double?
    var symbol: String   // SF Symbol chosen for the moment

    init(
        id: UUID = UUID(),
        title: String = "",
        note: String,
        coordinate: Coordinate,
        routeIndex: Int? = nil,
        speedKmh: Double? = nil,
        elevationMeters: Double? = nil,
        symbol: String = "mappin.circle.fill"
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.coordinate = coordinate
        self.routeIndex = routeIndex
        self.speedKmh = speedKmh
        self.elevationMeters = elevationMeters
        self.symbol = symbol
    }
}

// MARK: - Weather
//
// Historical weather at ride time (Open-Meteo in the web app).

struct Weather: Sendable {
    var temperatureC: Double
    var condition: String
    var windKph: Double
    var symbol: String   // SF Symbol for the condition
    var precipitationMm: Double? = nil

    var temperatureFormatted: String { String(format: "%.0f°", temperatureC) }
    var windFormatted: String { String(format: "%.0f km/h", windKph) }
    var precipitationFormatted: String? {
        guard let precipitationMm, precipitationMm >= 0.2 else { return nil }
        return String(format: "%.1f mm", precipitationMm)
    }
}
