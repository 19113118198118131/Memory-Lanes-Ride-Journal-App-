import Foundation

struct RideCoachAnalysis: Sendable {
    var score: Int?
    var scores: [RideCoachScore]
    var corners: [CornerTicket]
    var storageSummary: RideCoachStorageSummary?
    var debrief: String?
}

struct RideCoachStorageSummary: Encodable, Sendable {
    let version: Int
    let analysedAt: Date
    let scores: [String: Double]
    let corners: [RideCoachCornerSummary]
    let note: String?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case analysedAt = "at"
        case scores
        case corners
        case note
    }
}

struct RideCoachCornerSummary: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
    let headingDegrees: Int
    let apexKmh: Int
    let radiusMeters: Int
    let sweepDegrees: Int

    enum CodingKeys: String, CodingKey {
        case latitude = "la"
        case longitude = "ln"
        case headingDegrees = "hd"
        case apexKmh = "ak"
        case radiusMeters = "r"
        case sweepDegrees = "sw"
    }
}

private extension RideCoachStorageSummary {
    init(scores: [RideCoachScore], corners: [CornerEvent]) {
        self.version = 1
        self.analysedAt = Date()
        self.scores = Dictionary(uniqueKeysWithValues: scores.map { ($0.kind.storageKey, Double($0.value)) })
        self.corners = corners
            .sorted { $0.maxSignal > $1.maxSignal }
            .prefix(40)
            .map(RideCoachCornerSummary.init(event:))
        self.note = nil
    }

    static func insufficient(_ note: String) -> RideCoachStorageSummary {
        RideCoachStorageSummary(
            version: 1,
            analysedAt: Date(),
            scores: [:],
            corners: [],
            note: note
        )
    }
}

private extension RideCoachCornerSummary {
    init(event: CornerEvent) {
        latitude = (event.apexCoordinate.latitude * 100_000).rounded() / 100_000
        longitude = (event.apexCoordinate.longitude * 100_000).rounded() / 100_000
        headingDegrees = event.apexHeadingDegrees
        apexKmh = Int(event.apexKmh.rounded())
        radiusMeters = Int(event.radiusMeters.rounded())
        sweepDegrees = Int(event.sweepDegrees.rounded())
    }
}

struct RideCoachAnalyzer {
    private let minimumPointCount = 20

    func analyze(points: [RecordingPoint]) -> RideCoachAnalysis {
        guard points.count >= minimumPointCount else {
            return RideCoachAnalysis(
                score: nil,
                scores: [],
                corners: [],
                storageSummary: .insufficient("Not enough GPS points"),
                debrief: "Not enough GPS points for Ride Coach yet. A one-second GPX recording gives the best feedback."
            )
        }

        let projected = ProjectedTrack(points: points)
        guard projected.durationSeconds > 30, projected.totalDistanceMeters > 300 else {
            return RideCoachAnalysis(
                score: nil,
                scores: [],
                corners: [],
                storageSummary: .insufficient("Ride too short"),
                debrief: "This ride is too short for useful technique feedback."
            )
        }

        let speeds = movingAverage(projected.speedMetersPerSecond, window: 5)
        let acceleration = movingAverage(projected.longitudinalAcceleration(from: speeds), window: 3)
        let heading = projected.headingRadians
        let lateralLoad = movingAverage(projected.lateralAcceleration(from: speeds), window: 3)

        let cornerEvents = detectCorners(
            points: points,
            projected: projected,
            speeds: speeds,
            acceleration: acceleration,
            heading: heading,
            lateralLoad: lateralLoad
        )

        let brakingSmoothness = smoothnessScore(acceleration.filter { $0 < -0.9 })
        let throttleSmoothness = smoothnessScore(acceleration.filter { $0 > 0.7 })
        let entryScore = cornerEntryScore(cornerEvents)
        let exitScore = exitDriveScore(cornerEvents)
        let consistency = consistencyScore(cornerEvents)
        let scores = [entryScore, exitScore, brakingSmoothness, throttleSmoothness, consistency].compactMap { $0 }
        let score = scores.isEmpty ? nil : Int((scores.reduce(0, +) / Double(scores.count)).rounded())
        let coachScores = buildScores(
            entryScore: entryScore,
            exitScore: exitScore,
            brakingSmoothness: brakingSmoothness,
            throttleSmoothness: throttleSmoothness,
            consistency: consistency
        )

        return RideCoachAnalysis(
            score: score,
            scores: coachScores,
            corners: cornerEvents.map(\.ticket),
            storageSummary: RideCoachStorageSummary(scores: coachScores, corners: cornerEvents),
            debrief: buildDebrief(score: score, corners: cornerEvents, brakingSmoothness: brakingSmoothness, throttleSmoothness: throttleSmoothness)
        )
    }

    private func detectCorners(
        points: [RecordingPoint],
        projected: ProjectedTrack,
        speeds: [Double],
        acceleration: [Double],
        heading: [Double],
        lateralLoad: [Double]
    ) -> [CornerEvent] {
        var ranges: [(Int, Int)] = []
        var start: Int?
        var gap = 0
        let allowedGap = 3

        for index in lateralLoad.indices {
            let inCorner = lateralLoad[index] >= 1.25 && speeds[index] >= 4
            if inCorner {
                start = start ?? index
                gap = 0
            } else if let currentStart = start {
                gap += 1
                if gap > allowedGap {
                    ranges.append((currentStart, max(currentStart, index - gap)))
                    start = nil
                    gap = 0
                }
            }
        }
        if let start {
            ranges.append((start, lateralLoad.count - 1))
        }

        var events: [CornerEvent] = []
        for range in ranges {
            let start = range.0
            let end = range.1
            guard end - start >= 2 else { continue }

            let sweep = headingSweep(heading: heading, start: start, end: end)
            guard sweep >= 25, sweep <= 400 else { continue }

            let apex = (start...end).min { lhs, rhs in
                if abs(speeds[lhs] - speeds[rhs]) <= 0.05 {
                    return lateralLoad[lhs] > lateralLoad[rhs]
                }
                return speeds[lhs] < speeds[rhs]
            } ?? start

            let minRadius = projected.minimumRadius(start: start, end: end)
            let apexKmh = speeds[apex] * 3.6
            guard apexKmh >= 20, minRadius >= 12 else { continue }

            let brakeDepth = brakeDepth(start: start, apex: apex, acceleration: acceleration)
            let drive = mean(Array(acceleration[apex...end]))
            let apexPosition = Double(apex - start) / Double(max(1, end - start))
            let event = CornerEvent(
                start: start,
                apex: apex,
                end: end,
                apexCoordinate: points[apex].coordinate,
                apexHeadingDegrees: headingDegrees(heading[apex]),
                sweepDegrees: sweep,
                radiusMeters: minRadius,
                entryKmh: speeds[start] * 3.6,
                apexKmh: apexKmh,
                exitKmh: speeds[end] * 3.6,
                brakeDepth: brakeDepth,
                drive: drive,
                apexPosition: apexPosition,
                headingDelta: signedHeadingDelta(heading: heading, start: start, end: end)
            )
            events.append(event)
        }

        return Array(events.sorted { $0.maxSignal > $1.maxSignal }.prefix(12)).enumerated().map { offset, event in
            var copy = event
            copy.rank = offset + 1
            return copy
        }
    }

    private func brakeDepth(start: Int, apex: Int, acceleration: [Double]) -> Double {
        guard apex > start else { return 0 }
        var lastBrake: Int?
        for index in start...apex where acceleration[index] < -0.8 {
            lastBrake = index
        }
        guard let lastBrake else { return 0 }
        return Double(lastBrake - start) / Double(max(1, apex - start))
    }

    private func cornerEntryScore(_ events: [CornerEvent]) -> Double? {
        guard events.count >= 2 else { return nil }
        let settled = events.filter { $0.brakeDepth <= 0.4 }.count
        return Double(settled) / Double(events.count) * 100
    }

    private func exitDriveScore(_ events: [CornerEvent]) -> Double? {
        guard events.count >= 2 else { return nil }
        let meanDrive = mean(events.map { max(0, $0.drive) })
        return clamp(meanDrive / 1.2, 0, 1) * 100
    }

    private func consistencyScore(_ events: [CornerEvent]) -> Double? {
        guard events.count >= 3 else { return nil }
        let apexSpeeds = events.map(\.apexKmh)
        let avg = mean(apexSpeeds)
        guard avg > 0 else { return nil }
        return clamp(100 - (standardDeviation(apexSpeeds) / avg) * 260, 0, 100)
    }

    private func smoothnessScore(_ samples: [Double]) -> Double? {
        guard samples.count >= 4 else { return nil }
        let changes = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
        return clamp(100 - standardDeviation(changes) * 55, 0, 100)
    }

    private func buildScores(
        entryScore: Double?,
        exitScore: Double?,
        brakingSmoothness: Double?,
        throttleSmoothness: Double?,
        consistency: Double?
    ) -> [RideCoachScore] {
        [
            makeScore(kind: .cornerEntry, value: entryScore),
            makeScore(kind: .exitDrive, value: exitScore),
            makeScore(kind: .brakingFeel, value: brakingSmoothness),
            makeScore(kind: .throttleFeel, value: throttleSmoothness),
            makeScore(kind: .consistency, value: consistency)
        ].compactMap { $0 }
    }

    private func makeScore(kind: RideCoachScore.Kind, value: Double?) -> RideCoachScore? {
        guard let value, value.isFinite else { return nil }
        let rounded = Int(value.rounded())
        return RideCoachScore(kind: kind, value: rounded, caption: caption(for: kind, value: rounded))
    }

    private func caption(for kind: RideCoachScore.Kind, value: Int) -> String {
        switch kind {
        case .cornerEntry:
            if value >= 75 { return "Braking is mostly done before turn-in, so entries look settled." }
            if value >= 50 { return "Most entries are tidy, with a few corners still carrying brake pressure." }
            return "Braking often runs deep into corners. Focus on arriving settled before turn-in."
        case .exitDrive:
            if value >= 75 { return "Good progressive drive once the bike is picked up." }
            if value >= 50 { return "Exit drive is usable, but some corners stay flat after the apex." }
            return "Exits are quiet. Look up, pick the bike up, then roll on earlier and smoother."
        case .brakingFeel:
            if value >= 75 { return "Brake pressure looks progressive and controlled." }
            if value >= 50 { return "Braking is mostly smooth, with the occasional sharper input." }
            return "Braking looks abrupt. Practise squeezing the lever rather than grabbing it."
        case .throttleFeel:
            if value >= 75 { return "Throttle inputs look clean and progressive." }
            if value >= 50 { return "Throttle work is decent, with a few pulses on corner exits." }
            return "Throttle traces are jumpy. Aim for one smooth roll-on as the corner opens."
        case .consistency:
            if value >= 75 { return "Similar corners are getting repeatable treatment." }
            if value >= 50 { return "There is some rhythm, but similar corners vary ride to ride." }
            return "Similar corners are ridden quite differently. Pick one approach and repeat it."
        }
    }

    private func buildDebrief(score: Int?, corners: [CornerEvent], brakingSmoothness: Double?, throttleSmoothness: Double?) -> String {
        guard let score else {
            return corners.isEmpty
                ? "Ride Coach did not find enough cornering or braking data for technique feedback."
                : "Ride Coach found a few corners, but not enough repeatable events for a score yet."
        }

        let grade = score >= 85 ? "Silky smooth" : score >= 70 ? "Composed" : score >= 55 ? "Finding the rhythm" : "Plenty to gain"
        if let focusCorner = corners.first(where: { $0.brakeDepth > 0.55 }) {
            return "\(grade) ride: strongest takeaway is to finish braking a touch earlier before turn-in. Corner \(focusCorner.rank) carried braking deepest into the bend."
        }
        if let throttleSmoothness, throttleSmoothness < 55 {
            return "\(grade) ride: the line looks usable, but throttle inputs were a little jumpy. Next ride, roll on earlier and smoother once the exit opens."
        }
        if let brakingSmoothness, brakingSmoothness < 55 {
            return "\(grade) ride: the biggest gain is smoother brake pressure. Think squeeze, settle, turn."
        }
        if corners.count >= 3 {
            return "\(grade) ride: entries were mostly settled and the main corners had repeatable rhythm. Next ride, keep the same calm setup and look for cleaner exits."
        }
        return "\(grade) ride: route and speed traces were clean enough for a first coach score. A denser GPX log will sharpen corner feedback."
    }
}

private struct CornerEvent: Sendable {
    var rank = 1
    let start: Int
    let apex: Int
    let end: Int
    let apexCoordinate: Coordinate
    let apexHeadingDegrees: Int
    let sweepDegrees: Double
    let radiusMeters: Double
    let entryKmh: Double
    let apexKmh: Double
    let exitKmh: Double
    let brakeDepth: Double
    let drive: Double
    let apexPosition: Double
    let headingDelta: Double

    var maxSignal: Double { sweepDegrees / max(radiusMeters, 1) }

    var ticket: CornerTicket {
        CornerTicket(
            index: rank,
            shape: shape,
            entrySpeed: Int(entryKmh.rounded()),
            apexSpeed: Int(apexKmh.rounded()),
            exitSpeed: Int(exitKmh.rounded()),
            verdict: verdict,
            tip: tip
        )
    }

    private var shape: CornerShape {
        let isLeft = headingDelta >= 0
        if sweepDegrees > 150 {
            return isLeft ? .leftHairpin : .rightHairpin
        }
        if sweepDegrees > 80, radiusMeters < 90 {
            return isLeft ? .leftHairpin : .rightHairpin
        }
        return isLeft ? .leftSweeper : .rightSweeper
    }

    private var verdict: CornerTicket.Verdict {
        if brakeDepth > 0.6 { return .rushed }
        if apexPosition < 0.35 { return .early }
        if drive > 0.4, exitKmh > apexKmh * 1.06 { return .smooth }
        return .tidy
    }

    private var tip: String {
        if brakeDepth > 0.6 {
            return "Finish braking earlier so the bike is settled before turn-in."
        }
        if apexPosition < 0.35 {
            return "A later turn-in will give you more room and a calmer exit."
        }
        if drive < 0.1 {
            return "Pick the bike up and roll the throttle on progressively once you can see the exit."
        }
        return "Good shape: settled entry, clear apex, and a progressive exit."
    }
}

private struct ProjectedTrack {
    let points: [RecordingPoint]
    let xy: [(x: Double, y: Double)]
    let elapsed: [TimeInterval]
    let speedMetersPerSecond: [Double]
    let headingRadians: [Double]
    let totalDistanceMeters: Double
    let durationSeconds: TimeInterval

    init(points: [RecordingPoint]) {
        self.points = points
        let reference = points[points.count / 2]
        let kx = 111_320 * cos(reference.latitude * .pi / 180)
        let ky = 110_540.0
        xy = points.map { (($0.longitude - reference.longitude) * kx, ($0.latitude - reference.latitude) * ky) }
        let firstTime = points.first?.timestamp ?? Date()
        elapsed = points.map { max(0, $0.timestamp.timeIntervalSince(firstTime)) }

        var distance: Double = 0
        var speed = Array(repeating: 0.0, count: points.count)
        for index in points.indices.dropFirst() {
            let delta = hypot(xy[index].x - xy[index - 1].x, xy[index].y - xy[index - 1].y)
            distance += delta
            let dt = elapsed[index] - elapsed[index - 1]
            speed[index] = dt > 0 && dt < 60 ? delta / dt : speed[index - 1]
        }
        if speed.count > 1 {
            speed[0] = speed[1]
        }
        speedMetersPerSecond = speed

        var headings = Array(repeating: 0.0, count: points.count)
        for index in points.indices.dropFirst() {
            headings[index] = atan2(xy[index].y - xy[index - 1].y, xy[index].x - xy[index - 1].x)
        }
        if headings.count > 1 {
            headings[0] = headings[1]
        }
        headingRadians = headings
        totalDistanceMeters = distance
        durationSeconds = elapsed.last ?? 0
    }

    func longitudinalAcceleration(from speeds: [Double]) -> [Double] {
        guard points.count > 2 else { return Array(repeating: 0, count: points.count) }
        var output = Array(repeating: 0.0, count: points.count)
        for index in 1..<(points.count - 1) {
            let dt = elapsed[index + 1] - elapsed[index - 1]
            output[index] = dt > 0 ? (speeds[index + 1] - speeds[index - 1]) / dt : 0
        }
        return output
    }

    func lateralAcceleration(from speeds: [Double]) -> [Double] {
        guard points.count > 4 else { return Array(repeating: 0, count: points.count) }
        var output = Array(repeating: 0.0, count: points.count)
        for index in 2..<(points.count - 2) where speeds[index] >= 2 {
            let radius = circumradius(xy[index - 2], xy[index], xy[index + 2])
            if radius.isFinite, radius >= 5 {
                output[index] = speeds[index] * speeds[index] / min(radius, 100_000)
            }
        }
        return output
    }

    func minimumRadius(start: Int, end: Int) -> Double {
        guard points.count > 4 else { return .infinity }
        var minimum = Double.infinity
        let lower = max(2, start)
        let upper = min(points.count - 3, end)
        guard lower <= upper else { return minimum }
        for index in lower...upper {
            minimum = min(minimum, circumradius(xy[index - 2], xy[index], xy[index + 2]))
        }
        return minimum
    }
}

private func movingAverage(_ values: [Double], window: Int) -> [Double] {
    guard !values.isEmpty else { return [] }
    let half = max(1, window / 2)
    return values.indices.map { index in
        let lower = max(values.startIndex, index - half)
        let upper = min(values.endIndex - 1, index + half)
        let slice = values[lower...upper].filter(\.isFinite)
        guard !slice.isEmpty else { return 0 }
        return slice.reduce(0, +) / Double(slice.count)
    }
}

private func circumradius(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ c: (x: Double, y: Double)) -> Double {
    let ab = hypot(b.x - a.x, b.y - a.y)
    let bc = hypot(c.x - b.x, c.y - b.y)
    let ca = hypot(a.x - c.x, a.y - c.y)
    let area2 = abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
    guard area2 > 0.000001 else { return .infinity }
    return (ab * bc * ca) / (2 * area2)
}

private func headingSweep(heading: [Double], start: Int, end: Int) -> Double {
    guard end > start else { return 0 }
    var sweep = 0.0
    for index in (start + 1)...end {
        sweep += abs(normalizedAngle(heading[index] - heading[index - 1]))
    }
    return sweep * 180 / .pi
}

private func signedHeadingDelta(heading: [Double], start: Int, end: Int) -> Double {
    guard end > start else { return 0 }
    var delta = 0.0
    for index in (start + 1)...end {
        delta += normalizedAngle(heading[index] - heading[index - 1])
    }
    return delta
}

private func headingDegrees(_ heading: Double) -> Int {
    var degrees = heading * 180 / .pi
    while degrees < 0 { degrees += 360 }
    while degrees >= 360 { degrees -= 360 }
    return Int(degrees.rounded())
}

private func normalizedAngle(_ value: Double) -> Double {
    var angle = value
    while angle > .pi { angle -= 2 * .pi }
    while angle < -.pi { angle += 2 * .pi }
    return angle
}

private func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

private func standardDeviation(_ values: [Double]) -> Double {
    guard values.count > 1 else { return 0 }
    let avg = mean(values)
    return sqrt(values.reduce(0) { $0 + pow($1 - avg, 2) } / Double(values.count - 1))
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    max(lower, min(upper, value))
}
