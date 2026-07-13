import Foundation
import CoreLocation

struct GPXTrack: Sendable {
    let points: [RecordingPoint]
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let elevationGainMeters: Double
    let routePreview: [Coordinate]
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
        var previous: RecordingPoint?

        for point in points {
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
            previous = point
        }

        let duration = points.last?.timestamp.timeIntervalSince(points.first?.timestamp ?? Date()) ?? 0
        self.points = points
        distanceMeters = distance
        durationSeconds = max(0, duration)
        elevationGainMeters = gain
        routePreview = points.routePreview
        elevationSamples = samples
    }
}
