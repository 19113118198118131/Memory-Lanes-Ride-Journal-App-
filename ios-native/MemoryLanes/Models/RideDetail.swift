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
    /// The coaching debrief — one plain-English takeaway.
    var debrief: String?
}

struct RideCoachScore: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case cornerEntry
        case exitDrive
        case brakingFeel
        case throttleFeel
        case consistency

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
        repeatNote: String? = nil
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

    var temperatureFormatted: String { String(format: "%.0f°", temperatureC) }
    var windFormatted: String { String(format: "%.0f km/h", windKph) }
}
