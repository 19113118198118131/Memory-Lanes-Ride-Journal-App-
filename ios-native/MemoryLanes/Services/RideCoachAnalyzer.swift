import Foundation

struct RideCoachAnalysis: Sendable {
    var score: Int?
    var scores: [RideCoachScore]
    var corners: [CornerTicket]
    var analytics: RideAnalytics
    var riderCraft: RiderCraftAnalysis
    var storageSummary: RideCoachStorageSummary?
    var debrief: String?
    var trend: String?
}

struct RiderCraftRollout: Sendable {
    let surfacesCalibrationDebrief: Bool

    static let production = RiderCraftRollout(surfacesCalibrationDebrief: false)
    static let calibration = RiderCraftRollout(surfacesCalibrationDebrief: true)
}

struct RideCoachStorageSummary: Encodable, Sendable {
    let version: Int
    let analysedAt: Date
    let scores: [String: Double]
    let composition: [String: Int]
    let corners: [RideCoachCornerSummary]
    let riderCraft: RiderCraftStorageSummary?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case analysedAt = "at"
        case scores
        case composition = "comp"
        case corners
        case riderCraft = "craft"
        case note
    }
}

struct RideCoachCornerSummary: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let headingDegrees: Int
    let apexKmh: Int
    let radiusMeters: Int
    let sweepDegrees: Int
    let leanDegrees: Int?

    enum CodingKeys: String, CodingKey {
        case latitude = "la"
        case longitude = "ln"
        case headingDegrees = "hd"
        case apexKmh = "ak"
        case radiusMeters = "r"
        case sweepDegrees = "sw"
        case leanDegrees = "ld"
    }
}

private extension RideCoachStorageSummary {
    init(
        scores: [RideCoachScore],
        corners: [CornerEvent],
        composition: [RideCompositionSlice],
        riderCraft: RiderCraftAnalysis
    ) {
        self.version = 1
        self.analysedAt = Date()
        self.scores = Dictionary(uniqueKeysWithValues: scores.map { ($0.kind.storageKey, Double($0.value)) })
        self.composition = Dictionary(uniqueKeysWithValues: composition.map { ($0.kind.rawValue.lowercased(), Int($0.seconds.rounded())) })
        self.corners = corners
            .sorted { $0.maxSignal > $1.maxSignal }
            .prefix(40)
            .map(RideCoachCornerSummary.init(event:))
        self.riderCraft = RiderCraftStorageSummary(analysis: riderCraft)
        self.note = nil
    }

    static func insufficient(_ note: String) -> RideCoachStorageSummary {
        RideCoachStorageSummary(
            version: 1,
            analysedAt: Date(),
            scores: [:],
            composition: [:],
            corners: [],
            riderCraft: nil,
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
        leanDegrees = Int(event.leanDegrees.rounded())
    }
}

struct RideCoachAnalyzer {
    private let minimumPointCount = 20
    private let riderCraftRollout: RiderCraftRollout

    init(riderCraftRollout: RiderCraftRollout = .production) {
        self.riderCraftRollout = riderCraftRollout
    }

    func analyze(
        points: [RecordingPoint],
        pastCorners: [RideCoachCornerSummary] = [],
        recentScores: [String: Double] = [:]
    ) -> RideCoachAnalysis {
        guard points.count >= minimumPointCount else {
            return RideCoachAnalysis(
                score: nil,
                scores: [],
                corners: [],
                analytics: .empty,
                riderCraft: .unavailable("Not enough GPS points"),
                storageSummary: .insufficient("Not enough GPS points"),
                debrief: "Not enough GPS points for Ride Coach yet. A one-second GPX recording gives the best feedback.",
                trend: nil
            )
        }

        let projected = ProjectedTrack(points: points)
        guard projected.durationSeconds > 30, projected.totalDistanceMeters > 300 else {
            return RideCoachAnalysis(
                score: nil,
                scores: [],
                corners: [],
                analytics: .empty,
                riderCraft: .unavailable("Ride too short"),
                storageSummary: .insufficient("Ride too short"),
                debrief: "This ride is too short for useful technique feedback.",
                trend: nil
            )
        }

        let speeds = movingAverage(projected.speedMetersPerSecond, window: 5)
        let acceleration = movingAverage(projected.longitudinalAcceleration(from: speeds), window: 3)
        let jerk = projected.jerk(from: acceleration)
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

        let brakingZones = inputZones(
            kind: .braking,
            acceleration: acceleration,
            jerk: jerk,
            speeds: speeds,
            projected: projected
        )
        let driveZones = inputZones(
            kind: .drive,
            acceleration: acceleration,
            jerk: jerk,
            speeds: speeds,
            projected: projected
        )
        let riderCraft = RiderCraftAnalyzer().analyze(
            corners: cornerEvents.map(\.riderCraftSignal),
            brakingZones: brakingZones
        )
        let brakingSmoothness = zoneSmoothnessScore(brakingZones)
        let throttleSmoothness = zoneSmoothnessScore(driveZones)
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
        let composition = rideComposition(
            projected: projected,
            speeds: speeds,
            lateralLoad: lateralLoad,
            brakingZones: brakingZones,
            driveZones: driveZones
        )
        var analytics = RideAnalytics(
            acceleration: accelerationSeries(projected: projected, acceleration: acceleration),
            brakingZones: brakingZones,
            driveZones: driveZones,
            gripUsage: gripUsageSeries(projected: projected, acceleration: acceleration, lateralLoad: lateralLoad),
            cornerPoints: cornerEvents.map(\.analyticsPoint),
            composition: composition,
            insights: []
        )
        analytics.insights = buildInsights(
            analytics: analytics,
            points: points,
            scores: coachScores
        )

        return RideCoachAnalysis(
            score: score,
            scores: coachScores,
            corners: cornerEvents.prefix(10).map { event in
                event.ticket(repeatNote: repeatNote(for: event, pastCorners: pastCorners))
            },
            analytics: analytics,
            riderCraft: riderCraft,
            storageSummary: RideCoachStorageSummary(
                scores: coachScores,
                corners: cornerEvents,
                composition: composition,
                riderCraft: riderCraft
            ),
            debrief: debrief(scores: coachScores, riderCraft: riderCraft),
            trend: buildTrendLine(scores: coachScores, recentScores: recentScores)
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
        let allowedGap = max(2, Int((3 / projected.medianSampleInterval).rounded()))

        for index in lateralLoad.indices {
            let inCorner = lateralLoad[index] >= 1.3 &&
                projected.radiusMeters[index] <= 700 &&
                speeds[index] >= 4
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
            let minimumSamples = max(2, Int((2 / projected.medianSampleInterval).rounded()))
            guard end - start >= minimumSamples else { continue }

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
            let maxLateralAcceleration = lateralLoad[start...end].max() ?? 0
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
                headingDelta: signedHeadingDelta(heading: heading, start: start, end: end),
                maxLateralG: maxLateralAcceleration / 9.81,
                leanDegrees: atan(maxLateralAcceleration / 9.81) * 180 / .pi
            )
            events.append(event)
        }

        return events.sorted { $0.maxSignal > $1.maxSignal }.enumerated().map { offset, event in
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
        guard events.count >= 3 else { return nil }
        let settled = events.filter { $0.brakeDepth <= 0.4 }.count
        return Double(settled) / Double(events.count) * 100
    }

    private func exitDriveScore(_ events: [CornerEvent]) -> Double? {
        guard events.count >= 3 else { return nil }
        let meanDrive = mean(events.map { max(0, $0.drive) })
        return clamp(meanDrive / 1.2, 0, 1) * 100
    }

    private func consistencyScore(_ events: [CornerEvent]) -> Double? {
        guard events.count >= 3 else { return nil }
        let buckets = [
            events.filter { $0.radiusMeters < 60 },
            events.filter { $0.radiusMeters >= 60 && $0.radiusMeters < 180 },
            events.filter { $0.radiusMeters >= 180 }
        ]
        let variation = buckets.compactMap { bucket -> Double? in
            guard bucket.count >= 3 else { return nil }
            let speeds = bucket.map(\.apexKmh)
            let average = mean(speeds)
            guard average > 0 else { return nil }
            return standardDeviation(speeds) / average
        }
        guard !variation.isEmpty else { return nil }
        return clamp(100 - mean(variation) * 320, 0, 100)
    }

    private func zoneSmoothnessScore(_ zones: [RideInputZone]) -> Double? {
        guard zones.count >= 2 else { return nil }
        return mean(zones.map(\.smoothness))
    }

    private func inputZones(
        kind: RideInputZone.Kind,
        acceleration: [Double],
        jerk: [Double],
        speeds: [Double],
        projected: ProjectedTrack
    ) -> [RideInputZone] {
        var ranges: [(Int, Int)] = []
        var start: Int?
        let minimumSamples = max(2, Int((2 / projected.medianSampleInterval).rounded()))

        for index in acceleration.indices {
            let qualifies = speeds[index] > 3 && (kind == .braking
                ? acceleration[index] <= -1.4
                : acceleration[index] >= 1.2)
            if qualifies {
                start = start ?? index
            } else if let zoneStart = start {
                if index - zoneStart >= minimumSamples {
                    ranges.append((zoneStart, index - 1))
                }
                start = nil
            }
        }
        if let start, acceleration.count - start >= minimumSamples {
            ranges.append((start, acceleration.count - 1))
        }

        return ranges.map { start, end in
            let segment = Array(acceleration[start...end])
            let jerkStart = min(start + 1, end)
            let jerkSegment = Array(jerk[jerkStart...end])
            let peak = kind == .braking ? (segment.min() ?? 0) : (segment.max() ?? 0)
            return RideInputZone(
                kind: kind,
                startIndex: start,
                endIndex: end,
                startKm: projected.distanceMeters[start] / 1000,
                endKm: projected.distanceMeters[end] / 1000,
                peakAcceleration: peak,
                smoothness: clamp(100 - standardDeviation(jerkSegment) * 55, 0, 100)
            )
        }
    }

    private func rideComposition(
        projected: ProjectedTrack,
        speeds: [Double],
        lateralLoad: [Double],
        brakingZones: [RideInputZone],
        driveZones: [RideInputZone]
    ) -> [RideCompositionSlice] {
        var seconds = Dictionary(uniqueKeysWithValues: RideCompositionSlice.Kind.allCases.map { ($0, 0.0) })
        var braking = Array(repeating: false, count: speeds.count)
        var driving = Array(repeating: false, count: speeds.count)
        for zone in brakingZones {
            for index in zone.startIndex...zone.endIndex { braking[index] = true }
        }
        for zone in driveZones {
            for index in zone.startIndex...zone.endIndex { driving[index] = true }
        }

        for index in speeds.indices.dropFirst() {
            let dt = min(10, max(0, projected.elapsed[index] - projected.elapsed[index - 1]))
            let kind: RideCompositionSlice.Kind
            if speeds[index] < 1 {
                kind = .stopped
            } else if lateralLoad[index] >= 1.3 && projected.radiusMeters[index] <= 700 && speeds[index] >= 4 {
                kind = .cornering
            } else if braking[index] {
                kind = .braking
            } else if driving[index] {
                kind = .driving
            } else {
                kind = .cruising
            }
            seconds[kind, default: 0] += dt
        }
        return RideCompositionSlice.Kind.allCases.map {
            RideCompositionSlice(kind: $0, seconds: seconds[$0, default: 0])
        }
    }

    private func accelerationSeries(
        projected: ProjectedTrack,
        acceleration: [Double]
    ) -> [RideAccelerationSample] {
        let stride = max(1, Int(ceil(Double(acceleration.count) / 1500)))
        return Swift.stride(from: 0, to: acceleration.count, by: stride).map { index in
            RideAccelerationSample(
                index: index,
                distanceKm: projected.distanceMeters[index] / 1000,
                acceleration: acceleration[index]
            )
        }
    }

    private func gripUsageSeries(
        projected: ProjectedTrack,
        acceleration: [Double],
        lateralLoad: [Double]
    ) -> [GripUsagePoint] {
        guard acceleration.count > 2 else { return [] }
        let stride = max(1, Int(ceil(Double(acceleration.count) / 1500)))
        return Swift.stride(from: 1, to: acceleration.count - 1, by: stride).compactMap { index in
            guard projected.speedMetersPerSecond[index] >= 3 else { return nil }
            let headingChange = normalizedAngle(
                projected.headingRadians[index + 1] - projected.headingRadians[index - 1]
            )
            let sign = headingChange >= 0 ? 1.0 : -1.0
            return GripUsagePoint(
                index: index,
                lateralG: sign * lateralLoad[index] / 9.81,
                longitudinalG: acceleration[index] / 9.81
            )
        }
    }

    private func buildInsights(
        analytics: RideAnalytics,
        points: [RecordingPoint],
        scores: [RideCoachScore]
    ) -> [RideAnalyticsInsight] {
        let total = analytics.composition.map(\.seconds).reduce(0, +)
        func percentage(_ kind: RideCompositionSlice.Kind) -> Int {
            guard total > 0 else { return 0 }
            let value = analytics.composition.first(where: { $0.kind == kind })?.seconds ?? 0
            return Int((100 * value / total).rounded())
        }

        let combined = analytics.gripUsage.filter { abs($0.lateralG) > 0.12 && abs($0.longitudinalG) > 0.12 }.count
        let combinedPercent = analytics.gripUsage.isEmpty ? 0 : Int((100 * Double(combined) / Double(analytics.gripUsage.count)).rounded())
        let corneringGrip = analytics.gripUsage.filter { abs($0.lateralG) > 0.15 }
        let trailBraking = corneringGrip.filter { $0.longitudinalG < -0.12 }.count
        let trailPercent = corneringGrip.isEmpty ? 0 : Int((100 * Double(trailBraking) / Double(corneringGrip.count)).rounded())
        let signature = combinedPercent < 8 ? "a careful, upright rider" : combinedPercent < 18 ? "a composed road rider" : "an experienced, flowing rider"
        let trailText = trailPercent < 6 ? "almost no trail braking" : trailPercent < 20 ? "some trail braking (about \(trailPercent)%)" : "frequent trail braking (about \(trailPercent)%)"

        let lateralValues = analytics.cornerPoints.map(\.lateralG).sorted()
        let medianG = percentile(lateralValues, 0.5)
        let spreadG = percentile(lateralValues, 0.9) - percentile(lateralValues, 0.1)
        let pace = medianG < 0.28 ? "an easy, unhurried pace" : medianG < 0.42 ? "a moderate, purposeful pace" : medianG < 0.55 ? "a committed pace" : "a hard, determined pace"
        let reserve = medianG < 0.42 ? "with grip still in reserve" : "using a fair share of the estimated grip envelope"

        var climb = 0.0
        var descent = 0.0
        for (previous, current) in zip(points, points.dropFirst()) {
            let delta = current.elevationMeters - previous.elevationMeters
            if delta > 0 {
                climb += delta
            } else {
                descent -= delta
            }
        }

        let scoreMap = Dictionary(uniqueKeysWithValues: scores.map { ($0.kind, Double($0.value)) })
        let smoothValues = [scoreMap[.brakingFeel], scoreMap[.throttleFeel]].compactMap { $0 }
        let smoothAverage = smoothValues.isEmpty ? nil : mean(smoothValues)
        let smoothText = smoothAverage.map { value in
            value >= 80 ? "very smooth" : value >= 60 ? "smooth" : value >= 40 ? "a little uneven" : "busy"
        } ?? "not fully scored"
        let hardBrakingCount = analytics.brakingZones.filter { $0.peakAcceleration < -3.5 }.count

        return [
            RideAnalyticsInsight(
                kind: .grip,
                summary: "This ride has the fingerprint of \(signature).",
                detail: "You spent \(percentage(.cornering))% of moving time cornering and \(percentage(.cruising))% flowing between bends, with \(trailText). GPS-derived grip usage is approximate."
            ),
            RideAnalyticsInsight(
                kind: .corners,
                summary: analytics.cornerPoints.isEmpty
                    ? "Not enough significant corners for a corner profile."
                    : "You held \(pace) through the detected bends, around \(String(format: "%.2f", medianG)) g.",
                detail: "Across \(analytics.cornerPoints.count) detected corners, the lateral-load spread was \(String(format: "%.2f", spreadG)) g, \(reserve)."
            ),
            RideAnalyticsInsight(
                kind: .elevation,
                summary: "The road climbed \(Int(climb.rounded())) m and descended \(Int(descent.rounded())) m.",
                detail: "Elevation comes from the GPX stream and may include normal GPS altitude noise. Read it as the shape of the ride, not survey-grade height."
            ),
            RideAnalyticsInsight(
                kind: .inputs,
                summary: "\(analytics.brakingZones.count) braking zones, \(hardBrakingCount == 0 ? "none" : "\(hardBrakingCount)") firm; inputs were \(smoothText).",
                detail: "Ride Coach found \(analytics.driveZones.count) clear drive zones. Smoothness rewards progressive changes in braking and acceleration, never outright speed."
            )
        ]
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
            if value >= 80 { return "Braking is done before turn-in. The bike arrives settled." }
            if value >= 60 { return "Entries are mostly tidy. A few corners still carry braking in." }
            return "Braking often runs deep into corners. This is the clearest thing to work on."
        case .exitDrive:
            if value >= 80 { return "Strong, progressive throttle off the apex." }
            if value >= 60 { return "Decent drive out, with room for smoother corner exits." }
            return "Exits are flat. Pick the bike up, then roll the throttle on progressively."
        case .brakingFeel:
            if value >= 80 { return "Progressive on the lever. Smooth, controlled stops." }
            if value >= 60 { return "Mostly smooth braking with the occasional grab." }
            return "Braking is abrupt. Squeeze rather than snatch."
        case .throttleFeel:
            if value >= 80 { return "Clean, progressive acceleration." }
            if value >= 60 { return "Throttle work is decent, sometimes jumpy." }
            return "Acceleration comes in bursts. Smooth it out."
        case .consistency:
            if value >= 80 { return "Similar corners get near-identical treatment. Repeatable is skilled." }
            if value >= 60 { return "Corner speeds vary between similar bends." }
            return "Similar corners are ridden quite differently. Aim for repeatability."
        }
    }

    private func buildDebrief(scores: [RideCoachScore]) -> String? {
        guard scores.count >= 2,
              let strongest = scores.max(by: { $0.value < $1.value }),
              let weakest = scores.min(by: { $0.value < $1.value }) else { return nil }

        if strongest.value - weakest.value < 12 {
            return "A balanced ride across the board. Next ride, keep building on this consistency."
        }

        let strength: String
        switch strongest.kind {
        case .cornerEntry: strength = "Entries were settled, with braking done before turn-in"
        case .exitDrive: strength = "Drive off the corners was strong"
        case .brakingFeel: strength = "Braking was progressive and controlled"
        case .throttleFeel: strength = "Throttle work was clean"
        case .consistency: strength = "Similar corners got near-identical treatment"
        }

        let weakness: String
        let focus: String
        switch weakest.kind {
        case .cornerEntry:
            weakness = "braking often ran into the corners"
            focus = "finishing your braking before turn-in, so the bike arrives settled"
        case .exitDrive:
            weakness = "exits were flatter than they could be"
            focus = "picking the bike up earlier, then rolling the throttle on progressively"
        case .brakingFeel:
            weakness = "braking was on the abrupt side"
            focus = "squeezing the brake progressively rather than snatching it"
        case .throttleFeel:
            weakness = "throttle inputs were a little jumpy"
            focus = "smoother, earlier throttle once the corner opens up"
        case .consistency:
            weakness = "similar corners were ridden quite differently"
            focus = "treating similar corners the same way, ride after ride"
        }
        return "\(strength), but \(weakness). Next ride, focus on \(focus)."
    }

    private func debrief(scores: [RideCoachScore], riderCraft: RiderCraftAnalysis) -> String? {
        let coachDebrief = buildDebrief(scores: scores)
        guard riderCraftRollout.surfacesCalibrationDebrief,
              let craftLine = riderCraft.calibrationDebriefLine else { return coachDebrief }
        guard let coachDebrief else { return craftLine }
        return "\(coachDebrief) \(craftLine)"
    }

    private func buildTrendLine(scores: [RideCoachScore], recentScores: [String: Double]) -> String? {
        guard !scores.isEmpty, !recentScores.isEmpty else { return nil }
        let changes = scores.compactMap { score -> (RideCoachScore, Double)? in
            guard let previous = recentScores[score.kind.storageKey] else { return nil }
            return (score, Double(score.value) - previous)
        }
        guard let strongestChange = changes.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        let points = Int(abs(strongestChange.1).rounded())
        guard points >= 6 else { return "Right in line with your recent rides." }
        if strongestChange.1 > 0 {
            return "\(strongestChange.0.kind.title) is up \(points) points on your recent rides. Nice work."
        }
        return "\(strongestChange.0.kind.title) is \(points) points below your recent rides. One off day proves nothing; keep an eye on it."
    }

    private func repeatNote(for event: CornerEvent, pastCorners: [RideCoachCornerSummary]) -> String? {
        let matches = pastCorners.filter { past in
            haversineMeters(
                event.apexCoordinate.latitude,
                event.apexCoordinate.longitude,
                past.latitude,
                past.longitude
            ) < 35 && headingDifference(event.apexHeadingDegrees, past.headingDegrees) < 60
        }
        guard !matches.isEmpty else { return nil }

        let bestPast = matches.map(\.apexKmh).max() ?? 0
        let current = Int(event.apexKmh.rounded())
        let comparison = current > bestPast ? "new best" : "best \(bestPast) km/h"
        return "Ridden \(matches.count + 1)x · apex today \(current) km/h, \(comparison)"
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
    let maxLateralG: Double
    let leanDegrees: Double

    var maxSignal: Double { maxLateralG }

    var riderCraftSignal: RiderCraftCornerSignal {
        RiderCraftCornerSignal(
            cornerIndex: rank,
            startIndex: start,
            apexIndex: apex,
            endIndex: end,
            drive: drive,
            apexPosition: apexPosition,
            brakeDepth: brakeDepth
        )
    }

    var analyticsPoint: CornerAnalyticsPoint {
        CornerAnalyticsPoint(
            replayIndex: apex,
            radiusMeters: radiusMeters,
            apexKmh: apexKmh,
            lateralG: maxLateralG,
            leanDegrees: leanDegrees,
            sweepDegrees: sweepDegrees
        )
    }

    func ticket(repeatNote: String? = nil) -> CornerTicket {
        CornerTicket(
            index: rank,
            shape: shape,
            entrySpeed: Int(entryKmh.rounded()),
            apexSpeed: Int(apexKmh.rounded()),
            exitSpeed: Int(exitKmh.rounded()),
            verdict: verdict,
            tip: tip,
            repeatNote: repeatNote,
            replayIndex: apex,
            radiusMeters: Int(radiusMeters.rounded()),
            sweepDegrees: Int(sweepDegrees.rounded()),
            leanDegrees: Int(leanDegrees.rounded()),
            lateralG: maxLateralG
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
    let distanceMeters: [Double]
    let speedMetersPerSecond: [Double]
    let headingRadians: [Double]
    let radiusMeters: [Double]
    let medianSampleInterval: TimeInterval
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
        var distances = Array(repeating: 0.0, count: points.count)
        var speed = Array(repeating: 0.0, count: points.count)
        for index in points.indices.dropFirst() {
            let delta = hypot(xy[index].x - xy[index - 1].x, xy[index].y - xy[index - 1].y)
            distance += delta
            distances[index] = distance
            let dt = elapsed[index] - elapsed[index - 1]
            speed[index] = dt > 0 && dt < 60 ? delta / dt : speed[index - 1]
        }
        if speed.count > 1 {
            speed[0] = speed[1]
        }
        distanceMeters = distances
        speedMetersPerSecond = speed

        var headings = Array(repeating: 0.0, count: points.count)
        for index in points.indices.dropFirst() {
            headings[index] = atan2(xy[index].y - xy[index - 1].y, xy[index].x - xy[index - 1].x)
        }
        if headings.count > 1 {
            headings[0] = headings[1]
        }
        headingRadians = headings

        var radii = Array(repeating: Double.infinity, count: points.count)
        if points.count > 4 {
            for index in 2..<(points.count - 2) where speed[index] >= 2 {
                let radius = circumradius(xy[index - 2], xy[index], xy[index + 2])
                if radius.isFinite {
                    radii[index] = clamp(radius, 5, 100_000)
                }
            }
        }
        radiusMeters = radii

        let intervals = zip(elapsed, elapsed.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 && $0 < 60 }
            .sorted()
        medianSampleInterval = intervals.isEmpty ? 1 : intervals[intervals.count / 2]
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
            let radius = radiusMeters[index]
            if radius.isFinite, radius >= 5 {
                output[index] = speeds[index] * speeds[index] / min(radius, 100_000)
            }
        }
        return output
    }

    func minimumRadius(start: Int, end: Int) -> Double {
        guard points.count > 4 else { return .infinity }
        let lower = max(2, start)
        let upper = min(points.count - 3, end)
        guard lower <= upper else { return .infinity }
        return radiusMeters[lower...upper].min() ?? .infinity
    }

    func jerk(from acceleration: [Double]) -> [Double] {
        guard acceleration.count > 1 else { return Array(repeating: 0, count: acceleration.count) }
        var output = Array(repeating: 0.0, count: acceleration.count)
        for index in acceleration.indices.dropFirst() {
            let dt = elapsed[index] - elapsed[index - 1]
            output[index] = dt > 0 ? (acceleration[index] - acceleration[index - 1]) / dt : 0
        }
        return output
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

private func haversineMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let earthRadius = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let startLat = lat1 * .pi / 180
    let endLat = lat2 * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2) +
        cos(startLat) * cos(endLat) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * earthRadius * asin(sqrt(a))
}

private func headingDifference(_ lhs: Int, _ rhs: Int) -> Int {
    let diff = abs(lhs - rhs) % 360
    return diff > 180 ? 360 - diff : diff
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

private func percentile(_ sortedValues: [Double], _ fraction: Double) -> Double {
    guard !sortedValues.isEmpty else { return 0 }
    let index = min(
        sortedValues.count - 1,
        max(0, Int((Double(sortedValues.count - 1) * fraction).rounded()))
    )
    return sortedValues[index]
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    max(lower, min(upper, value))
}
