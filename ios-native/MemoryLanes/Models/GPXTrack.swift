import Foundation
import CoreLocation

struct GPXTrack: Sendable {
    let points: [RecordingPoint]
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let elevationGainMeters: Double
    let routePreview: [Coordinate]
    let replayPoints: [ReplayPoint]
    let elevationSamples: [ElevationSample]

    var startedAt: Date {
        points.first?.timestamp ?? Date()
    }

    var isValid: Bool {
        points.count > 1
    }
}

extension GPXTrack {
    init(points: [RecordingPoint]) {
        var distance: Double = 0
        var gain: Double = 0
        var samples: [ElevationSample] = []
        var replay: [ReplayPoint] = []
        var previous: RecordingPoint?
        let firstTimestamp = points.first?.timestamp ?? Date()

        for (index, point) in points.enumerated() {
            var segmentDistance: Double = 0
            var derivedSpeedMetersPerSecond: Double = 0
            if let previous {
                let from = previous.clLocation
                let to = point.clLocation
                segmentDistance = to.distance(from: from)
                distance += segmentDistance
                let elevationDelta = point.elevationMeters - previous.elevationMeters
                if elevationDelta > 1.5 {
                    gain += elevationDelta
                }
                let timeDelta = point.timestamp.timeIntervalSince(previous.timestamp)
                if timeDelta > 0 {
                    derivedSpeedMetersPerSecond = segmentDistance / timeDelta
                }
            }
            let replaySpeed = point.speedMetersPerSecond > 0
                ? point.speedMetersPerSecond
                : derivedSpeedMetersPerSecond
            samples.append(ElevationSample(distanceKm: distance / 1000, elevationM: point.elevationMeters))
            replay.append(
                ReplayPoint(
                    index: index,
                    coordinate: point.coordinate,
                    elapsedSeconds: max(0, point.timestamp.timeIntervalSince(firstTimestamp)),
                    distanceKm: distance / 1000,
                    elevationMeters: point.elevationMeters,
                    speedKmh: replaySpeed * 3.6
                )
            )
            previous = point
        }

        let duration = points.last?.timestamp.timeIntervalSince(firstTimestamp) ?? 0
        self.points = points
        distanceMeters = distance
        durationSeconds = max(0, duration)
        elevationGainMeters = gain
        routePreview = points.routePreview
        replayPoints = replay
        elevationSamples = samples
    }
}
