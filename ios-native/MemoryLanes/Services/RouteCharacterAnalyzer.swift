import Foundation

struct RouteCharacterAnalyzer: Sendable {
    static let modelVersion = 1

    func assess(
        coordinates: [Coordinate],
        context: RouteRoadContext = .geometryOnly,
        mood: RouteMood
    ) -> RouteCharacterAssessment {
        let profile = profile(for: coordinates)
        let score = weightedScore(profile: profile, context: context, mood: mood)
        return RouteCharacterAssessment(
            modelVersion: Self.modelVersion,
            score: Int((score * 100).rounded()),
            label: label(for: score, mood: mood),
            reasons: reasons(profile: profile, context: context, mood: mood),
            confidence: context.completeness >= 0.6 ? .enriched : .geometry,
            profile: profile
        )
    }

    func profile(for coordinates: [Coordinate]) -> RouteCharacterProfile {
        let sampled = RouteGeometrySampler.resample(coordinates, intervalMeters: 45)
        let distanceKm = RouteGeometrySampler.distanceMeters(coordinates) / 1_000
        guard sampled.count >= 3, distanceKm > 0 else {
            return RouteCharacterProfile(
                flow: 0,
                technicality: 0,
                variety: 0,
                straightRoadRatio: 1,
                distanceKm: distanceKm,
                turnsPerKm: 0
            )
        }

        let headings = zip(sampled, sampled.dropFirst()).map(RouteGeometrySampler.bearing)
        let signedTurns = zip(headings, headings.dropFirst()).map(RouteGeometrySampler.signedHeadingDelta)
        let meaningful = signedTurns.filter { abs($0) >= 4 }
        let tight = signedTurns.filter { abs($0) >= 14 }
        let straightRatio = Double(signedTurns.filter { abs($0) < 2.5 }.count) / Double(signedTurns.count)
        let turnsPerKm = Double(meaningful.count) / distanceKm

        let curveCoverage = Double(meaningful.count) / Double(signedTurns.count)
        let averageTurn = meaningful.map { abs($0) }.average ?? 0
        let technicality = clamp((averageTurn / 20) * 0.55 + (Double(tight.count) / Double(signedTurns.count)) * 0.45)

        let smoothPairs = zip(meaningful, meaningful.dropFirst()).filter { current, next in
            let sameDirection = current.sign == next.sign
            let change = abs(abs(current) - abs(next))
            return sameDirection && change <= 8
        }.count
        let continuity = meaningful.count > 1 ? Double(smoothPairs) / Double(meaningful.count - 1) : 0
        let flow = clamp(curveCoverage * 0.5 + continuity * 0.5)

        let headingBuckets = Set(headings.map { Int((($0 + 360).truncatingRemainder(dividingBy: 360)) / 30) })
        let directionVariety = Double(headingBuckets.count) / 12
        let directionChanges = zip(signedTurns, signedTurns.dropFirst()).filter { $0.sign != $1.sign }.count
        let alternating = signedTurns.count > 1 ? Double(directionChanges) / Double(signedTurns.count - 1) : 0
        let variety = clamp(directionVariety * 0.65 + alternating * 0.35)

        return RouteCharacterProfile(
            flow: flow,
            technicality: technicality,
            variety: variety,
            straightRoadRatio: straightRatio,
            distanceKm: distanceKm,
            turnsPerKm: turnsPerKm
        )
    }

    private func weightedScore(
        profile: RouteCharacterProfile,
        context: RouteRoadContext,
        mood: RouteMood
    ) -> Double {
        let geometry: Double
        switch mood {
        case .flowing:
            geometry = profile.flow * 0.58 + profile.variety * 0.22 + profile.technicality * 0.20
        case .twisty:
            geometry = profile.technicality * 0.56 + profile.variety * 0.25 + profile.flow * 0.19
        case .scenic:
            geometry = profile.variety * 0.52 + profile.flow * 0.30 + profile.technicality * 0.18
        case .relaxed:
            geometry = profile.flow * 0.42 + (1 - profile.technicality) * 0.36 + profile.variety * 0.22
        }

        var score = geometry - profile.straightRoadRatio * 0.24
        if let scenic = context.scenicLandRatio {
            score += scenic * (mood == .scenic ? 0.34 : 0.12)
        }
        if let urban = context.urbanRatio { score -= urban * 0.28 }
        if let motorway = context.motorwayRatio { score -= motorway * 0.42 }
        if let surface = context.unsuitableSurfaceRatio { score -= surface * 0.65 }
        if let elevation = context.elevationGainMeters, profile.distanceKm > 0 {
            let climbing = clamp((elevation / profile.distanceKm) / 18)
            score += climbing * (mood == .scenic || mood == .twisty ? 0.12 : 0.04)
        }
        return clamp(score)
    }

    private func reasons(
        profile: RouteCharacterProfile,
        context: RouteRoadContext,
        mood: RouteMood
    ) -> [String] {
        var values: [(Double, String)] = [
            (profile.flow, "Sustained bends with consistent direction changes"),
            (profile.technicality, "Frequent tighter changes in road direction"),
            (profile.variety, "Varied headings instead of a single road corridor")
        ]
        if let scenic = context.scenicLandRatio {
            values.append((scenic, "Passes through more open or natural surroundings"))
        }
        if profile.straightRoadRatio > 0.62 {
            values.append((1 - profile.straightRoadRatio, "Includes a meaningful proportion of straight road"))
        }
        if let motorway = context.motorwayRatio, motorway > 0.15 {
            values.append((1 - motorway, "Motorway exposure reduces the road-character score"))
        }

        let preferred: [String]
        switch mood {
        case .flowing: preferred = ["Sustained", "Varied"]
        case .twisty: preferred = ["Frequent", "Sustained"]
        case .scenic: preferred = ["open", "Varied"]
        case .relaxed: preferred = ["Sustained", "straight"]
        }
        return values
            .sorted { left, right in
                let leftBoost = preferred.contains { left.1.contains($0) } ? 0.25 : 0
                let rightBoost = preferred.contains { right.1.contains($0) } ? 0.25 : 0
                return left.0 + leftBoost > right.0 + rightBoost
            }
            .prefix(2)
            .map(\.1)
    }

    private func label(for score: Double, mood: RouteMood) -> String {
        switch score {
        case 0.78...: "Strong \(mood.title.lowercased()) character"
        case 0.58...: "Promising \(mood.title.lowercased()) character"
        case 0.38...: "Mixed road character"
        default: "Calmer road geometry"
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

private enum RouteGeometrySampler {
    static func resample(_ coordinates: [Coordinate], intervalMeters: Double) -> [Coordinate] {
        guard coordinates.count > 1, intervalMeters > 0 else { return coordinates }
        var result = [coordinates[0]]
        var distanceToNext = intervalMeters
        var start = coordinates[0]

        for end in coordinates.dropFirst() {
            var segmentDistance = distanceMeters(start, end)
            while segmentDistance >= distanceToNext, segmentDistance > 0 {
                let progress = distanceToNext / segmentDistance
                let point = Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * progress,
                    longitude: start.longitude + (end.longitude - start.longitude) * progress
                )
                result.append(point)
                start = point
                segmentDistance = distanceMeters(start, end)
                distanceToNext = intervalMeters
            }
            distanceToNext -= segmentDistance
            start = end
        }
        if result.last != coordinates.last, let last = coordinates.last { result.append(last) }
        return result
    }

    static func distanceMeters(_ coordinates: [Coordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + distanceMeters($1.0, $1.1) }
    }

    static func distanceMeters(_ from: Coordinate, _ to: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let deltaLatitude = (to.latitude - from.latitude) * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let startLatitude = from.latitude * .pi / 180
        let endLatitude = to.latitude * .pi / 180
        let value = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
            sin(deltaLongitude / 2) * sin(deltaLongitude / 2) * cos(startLatitude) * cos(endLatitude)
        return earthRadius * 2 * atan2(sqrt(value), sqrt(1 - value))
    }

    static func bearing(_ pair: (Coordinate, Coordinate)) -> Double {
        let from = pair.0
        let to = pair.1
        let startLatitude = from.latitude * .pi / 180
        let endLatitude = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)
        return atan2(y, x) * 180 / .pi
    }

    static func signedHeadingDelta(_ pair: (Double, Double)) -> Double {
        var delta = pair.1 - pair.0
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }
}

private extension Array where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
