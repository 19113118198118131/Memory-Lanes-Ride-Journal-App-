import Foundation

struct LimitPointAnalyzer: Sendable {
    static let modelVersion = 1

    let obstructionOffsetMeters: Double
    let reactionSeconds: Double
    let dryDeceleration: Double
    let wetDeceleration: Double

    init(
        obstructionOffsetMeters: Double = 5,
        reactionSeconds: Double = 1,
        dryDeceleration: Double = 7,
        wetDeceleration: Double = 4.5
    ) {
        self.obstructionOffsetMeters = obstructionOffsetMeters
        self.reactionSeconds = reactionSeconds
        self.dryDeceleration = dryDeceleration
        self.wetDeceleration = wetDeceleration
    }

    func analyze(route: [Coordinate], referenceSpeedKmh: Double, wet: Bool = false) -> LimitPointAnalysis {
        let samples = route.enumerated().map {
            LimitPointSample(coordinate: $0.element, speedKmh: nil, replayIndex: $0.offset)
        }
        return analyze(samples: samples, fallbackSpeedKmh: referenceSpeedKmh, wet: wet)
    }

    func analyze(replayPoints: [ReplayPoint], wet: Bool = false) -> LimitPointAnalysis {
        let samples = replayPoints.map {
            LimitPointSample(coordinate: $0.coordinate, speedKmh: $0.speedKmh, replayIndex: $0.index)
        }
        return analyze(samples: samples, fallbackSpeedKmh: 0, wet: wet)
    }

    func sightDistance(radiusMeters: Double) -> Double {
        guard radiusMeters > 0 else { return 0 }
        let ratio = min(max(1 - obstructionOffsetMeters / radiusMeters, -1), 1)
        return 2 * radiusMeters * acos(ratio)
    }

    func stoppingDistance(speedKmh: Double, wet: Bool) -> Double {
        let speed = max(speedKmh, 0) / 3.6
        let deceleration = wet ? wetDeceleration : dryDeceleration
        return speed * reactionSeconds + speed * speed / (2 * deceleration)
    }

    private func analyze(
        samples: [LimitPointSample],
        fallbackSpeedKmh: Double,
        wet: Bool
    ) -> LimitPointAnalysis {
        guard samples.count >= 7 else {
            return empty(samples: samples, wet: wet, usesRecordedSpeed: samples.contains { $0.speedKmh != nil })
        }

        let coordinates = samples.map(\.coordinate)
        let cumulative = cumulativeDistances(coordinates)
        let localGeometry = samples.indices.map { index in
            geometry(at: index, coordinates: coordinates, cumulative: cumulative)
        }
        var ranges: [ClosedRange<Int>] = []
        var start: Int?
        var gap = 0

        for index in localGeometry.indices {
            let geometry = localGeometry[index]
            let isCorner = geometry.radius >= 12 && geometry.radius <= 450 && abs(geometry.turnDegrees) >= 2.5
            if isCorner {
                start = start ?? index
                gap = 0
            } else if let currentStart = start {
                gap += 1
                if gap > 2 {
                    ranges.append(currentStart...max(currentStart, index - gap))
                    start = nil
                    gap = 0
                }
            }
        }
        if let start { ranges.append(start...(samples.count - 1)) }

        let deceleration = wet ? wetDeceleration : dryDeceleration
        let rawCorners = ranges.compactMap { range -> LimitPointCorner? in
            let sweep = sweepDegrees(in: range, coordinates: coordinates)
            guard abs(sweep) >= 20 else { return nil }
            let candidateIndices = range.filter { localGeometry[$0].radius.isFinite && localGeometry[$0].radius > 0 }
            guard let apex = candidateIndices.min(by: { localGeometry[$0].radius < localGeometry[$1].radius }) else { return nil }
            let radius = localGeometry[apex].radius
            let speed = max(samples[range.lowerBound].speedKmh ?? fallbackSpeedKmh, 0)
            let sight = sightDistance(radiusMeters: radius)
            let stopping = stoppingDistance(speedKmh: speed, wet: wet)
            let margin = sight - stopping
            return LimitPointCorner(
                index: 0,
                startIndex: range.lowerBound,
                apexIndex: apex,
                endIndex: range.upperBound,
                replayIndex: samples[apex].replayIndex,
                coordinate: samples[apex].coordinate,
                direction: sweep >= 0 ? .left : .right,
                radiusMeters: radius,
                sweepDegrees: abs(sweep),
                referenceSpeedKmh: speed,
                sightDistanceMeters: sight,
                stoppingDistanceMeters: stopping,
                marginMeters: margin,
                severity: severity(for: margin)
            )
        }

        let corners = rawCorners.enumerated().map { offset, corner in
            LimitPointCorner(
                index: offset + 1,
                startIndex: corner.startIndex,
                apexIndex: corner.apexIndex,
                endIndex: corner.endIndex,
                replayIndex: corner.replayIndex,
                coordinate: corner.coordinate,
                direction: corner.direction,
                radiusMeters: corner.radiusMeters,
                sweepDegrees: corner.sweepDegrees,
                referenceSpeedKmh: corner.referenceSpeedKmh,
                sightDistanceMeters: corner.sightDistanceMeters,
                stoppingDistanceMeters: corner.stoppingDistanceMeters,
                marginMeters: corner.marginMeters,
                severity: corner.severity
            )
        }

        return LimitPointAnalysis(
            modelVersion: Self.modelVersion,
            route: coordinates,
            corners: corners,
            obstructionOffsetMeters: obstructionOffsetMeters,
            reactionSeconds: reactionSeconds,
            decelerationMetersPerSecondSquared: deceleration,
            usesRecordedSpeed: samples.contains { $0.speedKmh != nil },
            wetModel: wet,
            geometrySource: samples.contains { $0.speedKmh != nil } ? .recordedTrack : .plannedRoute,
            obstructionSource: .fixedResearch,
            confidence: .low
        )
    }

    private func empty(samples: [LimitPointSample], wet: Bool, usesRecordedSpeed: Bool) -> LimitPointAnalysis {
        LimitPointAnalysis(
            modelVersion: Self.modelVersion,
            route: samples.map(\.coordinate),
            corners: [],
            obstructionOffsetMeters: obstructionOffsetMeters,
            reactionSeconds: reactionSeconds,
            decelerationMetersPerSecondSquared: wet ? wetDeceleration : dryDeceleration,
            usesRecordedSpeed: usesRecordedSpeed,
            wetModel: wet,
            geometrySource: usesRecordedSpeed ? .recordedTrack : .plannedRoute,
            obstructionSource: .fixedResearch,
            confidence: .low
        )
    }

    private func geometry(
        at index: Int,
        coordinates: [Coordinate],
        cumulative: [Double]
    ) -> (radius: Double, turnDegrees: Double) {
        guard index > 0, index < coordinates.count - 1 else { return (.infinity, 0) }
        let before = indexBefore(index, by: 12, cumulative: cumulative)
        let after = indexAfter(index, by: 12, cumulative: cumulative)
        guard before < index, after > index else { return (.infinity, 0) }
        let a = projected(coordinates[before], around: coordinates[index])
        let b = (x: 0.0, y: 0.0)
        let c = projected(coordinates[after], around: coordinates[index])
        let ab = hypot(a.x - b.x, a.y - b.y)
        let bc = hypot(b.x - c.x, b.y - c.y)
        let ca = hypot(c.x - a.x, c.y - a.y)
        let twiceArea = abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
        let radius = twiceArea > 0.01 ? (ab * bc * ca) / (2 * twiceArea) : .infinity
        let firstHeading = atan2(b.x - a.x, b.y - a.y)
        let secondHeading = atan2(c.x - b.x, c.y - b.y)
        let turn = normalisedRadians(secondHeading - firstHeading) * 180 / .pi
        return (radius, turn)
    }

    private func cumulativeDistances(_ coordinates: [Coordinate]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var values = Array(repeating: 0.0, count: coordinates.count)
        for index in 1..<coordinates.count {
            values[index] = values[index - 1] + distance(coordinates[index - 1], coordinates[index])
        }
        return values
    }

    private func indexBefore(_ index: Int, by meters: Double, cumulative: [Double]) -> Int {
        var candidate = index
        while candidate > 0, cumulative[index] - cumulative[candidate] < meters { candidate -= 1 }
        return candidate
    }

    private func indexAfter(_ index: Int, by meters: Double, cumulative: [Double]) -> Int {
        var candidate = index
        while candidate < cumulative.count - 1, cumulative[candidate] - cumulative[index] < meters { candidate += 1 }
        return candidate
    }

    private func sweepDegrees(in range: ClosedRange<Int>, coordinates: [Coordinate]) -> Double {
        guard range.upperBound > range.lowerBound + 1 else { return 0 }
        var sweep = 0.0
        for index in (range.lowerBound + 1)..<range.upperBound {
            let incoming = bearing(coordinates[index - 1], coordinates[index])
            let outgoing = bearing(coordinates[index], coordinates[index + 1])
            sweep += normalisedRadians(outgoing - incoming) * 180 / .pi
        }
        return sweep
    }

    private func severity(for margin: Double) -> LimitPointCorner.Severity {
        if margin < -20 { return .severe }
        if margin < 0 { return .beyondView }
        if margin < 20 { return .thin }
        return .room
    }

    private func projected(_ coordinate: Coordinate, around origin: Coordinate) -> (x: Double, y: Double) {
        let x = (coordinate.longitude - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180)
        let y = (coordinate.latitude - origin.latitude) * 111_320
        return (x, y)
    }

    private func distance(_ first: Coordinate, _ second: Coordinate) -> Double {
        let value = projected(first, around: second)
        return hypot(value.x, value.y)
    }

    private func bearing(_ first: Coordinate, _ second: Coordinate) -> Double {
        let delta = projected(second, around: first)
        return atan2(delta.x, delta.y)
    }

    private func normalisedRadians(_ angle: Double) -> Double {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }
}
