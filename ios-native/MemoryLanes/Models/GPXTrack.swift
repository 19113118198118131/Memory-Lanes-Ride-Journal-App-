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
            if let previous {
                let from = previous.clLocation
                let to = point.clLocation
                distance += to.distance(from: from)
                let elevationDelta = point.elevationMeters - previous.elevationMeters
                if elevationDelta > 1.5 {
                    gain += elevationDelta
                }
            }
            samples.append(ElevationSample(distanceKm: distance / 1000, elevationM: point.elevationMeters))
            replay.append(
                ReplayPoint(
                    index: index,
                    coordinate: point.coordinate,
                    elapsedSeconds: max(0, point.timestamp.timeIntervalSince(firstTimestamp)),
                    distanceKm: distance / 1000,
                    elevationMeters: point.elevationMeters,
                    speedKmh: point.speedMetersPerSecond * 3.6
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
