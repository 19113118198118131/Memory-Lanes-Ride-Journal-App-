import Foundation

struct RideFeatureExtractor {
    func extract(ride: Ride, points: [RecordingPoint], scores: [RideCoachScore], corners: [CornerTicket]) -> RideFeatureRecord {
        let distanceKm = ride.distanceMeters / 1_000
        let durationMin = ride.durationSeconds / 60
        let averageRadius = corners.compactMap(\.radiusMeters).map(Double.init).average
        return RideFeatureRecord(
            schemaVersion: 1,
            route: .init(
                distanceKm: distanceKm.rounded(to: 1),
                durationMin: durationMin.rounded(),
                elevationGainM: ride.elevationGainMeters.rounded(),
                avgSpeedKmh: durationMin > 0 ? (distanceKm / (durationMin / 60)).rounded(to: 1) : nil,
                turnsPerKm: RouteGeometry.turnsPerKm(points.map(\.coordinate), distanceKm: distanceKm)?.rounded(to: 2),
                cornerCount: corners.isEmpty ? nil : corners.count,
                avgCornerRadiusM: averageRadius?.rounded()
            ),
            technique: .init(
                cornerEntry: scores.value(for: .cornerEntry),
                exitDrive: scores.value(for: .exitDrive),
                brakingSmoothness: scores.value(for: .brakingFeel),
                throttleSmoothness: scores.value(for: .throttleFeel),
                consistency: scores.value(for: .consistency)
            )
        )
    }
}

struct RideRecommendationEngine: Sendable {
    private static let weights = [1.0, 0.7, 1.2]
    private let neighbours: [Neighbour]
    private let mean: [Double]
    private let standardDeviation: [Double]
    private let likedMean: [Double]?

    let ratedCount: Int
    var isReady: Bool { ratedCount >= 4 }

    init(ratedRides: [RatedRideFeatures]) {
        let clean = ratedRides.compactMap { ride -> ([Double], Double)? in
            guard let vector = ride.features.matchVector, ride.enjoyment.isFinite else { return nil }
            return (vector.values, ride.enjoyment)
        }
        ratedCount = clean.count
        let calculatedMean = Self.columnMean(clean.map(\.0))
        let calculatedDeviation = Self.columnStandardDeviation(clean.map(\.0), mean: calculatedMean)
        mean = calculatedMean
        standardDeviation = calculatedDeviation
        neighbours = clean.map { values, enjoyment in
            Neighbour(z: Self.standardize(values, mean: calculatedMean, deviation: calculatedDeviation), enjoyment: enjoyment)
        }
        let liked = clean.filter { $0.1 >= 4 }.map(\.0)
        likedMean = liked.isEmpty ? nil : Self.columnMean(liked)
    }

    func score(_ candidate: RouteMatchVector) -> RouteRecommendation? {
        guard isReady else { return nil }
        let z = Self.standardize(candidate.values, mean: mean, deviation: standardDeviation)
        let ranked = neighbours
            .map { ($0.distance(to: z), $0.enjoyment) }
            .sorted { $0.0 < $1.0 }
            .prefix(min(5, neighbours.count))
        var weightSum = 0.0
        var enjoymentSum = 0.0
        for (distance, enjoyment) in ranked {
            let weight = 1 / (0.35 + distance)
            weightSum += weight
            enjoymentSum += weight * enjoyment
        }
        guard weightSum > 0 else { return nil }
        let predicted = enjoymentSum / weightSum
        let nearest = ranked.first?.0 ?? .infinity
        let confidence: RouteRecommendation.Confidence = nearest < 1 ? .high : nearest < 2.2 ? .medium : .low
        return RouteRecommendation(
            matchPercent: Int((min(max((predicted - 1) / 4, 0), 1) * 100).rounded()),
            predictedEnjoyment: predicted.rounded(to: 2),
            confidence: confidence,
            reasons: reasons(for: candidate.values)
        )
    }

    private func reasons(for values: [Double]) -> [String] {
        guard let likedMean else { return ["Matched against the rides you have rated so far"] }
        let labels = ["ride length", "climbing", "corner density"]
        var reasons: [(Bool, String)] = []
        for index in values.indices where likedMean[index] != 0 {
            let ratio = values[index] / likedMean[index]
            if 0.85...1.15 ~= ratio {
                reasons.append((true, "Similar \(labels[index]) to rides you rated highly"))
            } else if index == 0 {
                reasons.append((false, ratio > 1.15 ? "Longer than your usual ride length" : "Shorter than your usual ride length"))
            } else if index == 1 {
                reasons.append((false, ratio > 1.15 ? "Hillier than your favourites" : "Flatter than your favourites"))
            } else {
                reasons.append((false, ratio > 1.15 ? "More corners than your usual favourites" : "Calmer, fewer corners than your usual favourites"))
            }
        }
        return reasons.sorted { $0.0 && !$1.0 }.prefix(3).map(\.1)
    }

    private static func columnMean(_ vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [0, 0, 0] }
        return first.indices.map { index in vectors.map { $0[index] }.reduce(0, +) / Double(vectors.count) }
    }

    private static func columnStandardDeviation(_ vectors: [[Double]], mean: [Double]) -> [Double] {
        guard !vectors.isEmpty else { return [1, 1, 1] }
        return mean.indices.map { index in
            let variance = vectors.map { pow($0[index] - mean[index], 2) }.reduce(0, +) / Double(vectors.count)
            let value = sqrt(variance)
            return value == 0 ? 1 : value
        }
    }

    private static func standardize(_ values: [Double], mean: [Double], deviation: [Double]) -> [Double] {
        values.indices.map { (($0 < mean.count ? values[$0] - mean[$0] : 0) / deviation[$0]) * weights[$0] }
    }

    private struct Neighbour: Sendable {
        let z: [Double]
        let enjoyment: Double

        func distance(to other: [Double]) -> Double {
            sqrt(z.indices.map { pow(z[$0] - other[$0], 2) }.reduce(0, +))
        }
    }
}

extension RouteGeometry {
    static func turnsPerKm(_ points: [Coordinate], distanceKm: Double? = nil) -> Double? {
        guard points.count >= 3 else { return nil }
        let distance = distanceKm ?? points.totalDistanceKm
        guard distance > 0 else { return nil }
        var turns = 0
        var previousBearing: Double?
        for (from, to) in zip(points, points.dropFirst()) {
            let bearing = bearing(from: from, to: to)
            if let previousBearing {
                var delta = abs(bearing - previousBearing)
                if delta > 180 { delta = 360 - delta }
                if delta > 8 { turns += 1 }
            }
            previousBearing = bearing
        }
        return Double(turns) / distance
    }

    private static func bearing(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

private extension RideFeatureRecord {
    var matchVector: RouteMatchVector? {
        guard let distanceKm = route.distanceKm,
              let elevationGainM = route.elevationGainM,
              let turnsPerKm = route.turnsPerKm else { return nil }
        return RouteMatchVector(distanceKm: distanceKm, elevationGainM: elevationGainM, turnsPerKm: turnsPerKm)
    }
}

private extension Array where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}

private extension Array where Element == Coordinate {
    var totalDistanceKm: Double {
        zip(self, dropFirst()).reduce(0) { result, pair in
            let earthRadiusKm = 6_371.0
            let deltaLatitude = (pair.1.latitude - pair.0.latitude) * .pi / 180
            let deltaLongitude = (pair.1.longitude - pair.0.longitude) * .pi / 180
            let startLatitude = pair.0.latitude * .pi / 180
            let endLatitude = pair.1.latitude * .pi / 180
            let value = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
                sin(deltaLongitude / 2) * sin(deltaLongitude / 2) * cos(startLatitude) * cos(endLatitude)
            return result + earthRadiusKm * 2 * atan2(sqrt(value), sqrt(1 - value))
        }
    }
}

private extension Array where Element == RideCoachScore {
    func value(for kind: RideCoachScore.Kind) -> Double? {
        first { $0.kind == kind }.map { Double($0.value) }
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
