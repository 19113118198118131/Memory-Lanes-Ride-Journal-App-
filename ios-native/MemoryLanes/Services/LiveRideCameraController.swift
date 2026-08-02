import Foundation

enum LiveRideCameraMode: String, CaseIterable, Sendable {
    case immersive
    case headingUp
    case northUp

    var symbol: String {
        switch self {
        case .immersive: "view.3d"
        case .headingUp: "location.north.fill"
        case .northUp: "safari.fill"
        }
    }

    var title: String {
        switch self {
        case .immersive: "Immersive"
        case .headingUp: "Heading up"
        case .northUp: "North up"
        }
    }

    var next: LiveRideCameraMode {
        switch self {
        case .immersive: .headingUp
        case .headingUp: .northUp
        case .northUp: .immersive
        }
    }
}

struct LiveRideCameraSample: Equatable, Sendable {
    let coordinate: Coordinate
    let timestamp: Date
    let speedMetersPerSecond: Double
    let speedAccuracyMetersPerSecond: Double?
    let courseDegrees: Double
    let courseAccuracyDegrees: Double?
    let fallbackBearingDegrees: Double?
    let viewportHeightPoints: Double
    let mode: LiveRideCameraMode
    let reduceMotion: Bool
}

struct LiveRideCameraState: Equatable, Sendable {
    let center: Coordinate
    let cameraDistanceMeters: Double
    let bearingDegrees: Double
    let travelBearingDegrees: Double
    let pitchDegrees: Double
    let lookaheadMeters: Double
    let filteredSpeedMetersPerSecond: Double
    let holdsBearing: Bool
    let animationDuration: TimeInterval
}

struct LiveRideCameraController: Sendable {
    struct Configuration: Equatable, Sendable {
        var horizonSeconds = 20.0
        var minimumLookaheadMeters = 110.0
        var minimumCameraDistanceMeters = 150.0
        var maximumCameraDistanceMeters = 1_200.0
        var bearingEngageSpeedKmh = 5.0
        var bearingReleaseSpeedKmh = 3.5
        var maximumBearingStepDegrees = 28.0
        var speedSmoothingSeconds = 2.2
        var bearingSmoothingSeconds = 0.85
    }

    private let configuration: Configuration
    private var filteredSpeed: Double?
    private var smoothedBearing: Double?
    private var lastTravelBearing: Double?
    private var lastCoordinate: Coordinate?
    private var lastTimestamp: Date?
    private var bearingTrackingActive = false

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func update(_ sample: LiveRideCameraSample) -> LiveRideCameraState {
        let elapsed = elapsedSeconds(to: sample.timestamp)
        let derivedMotion = derivedMotion(to: sample.coordinate, elapsed: elapsed)
        let measuredSpeed = reliableSpeed(sample, derivedSpeed: derivedMotion.speed)
        let speedAlpha = smoothingAlpha(elapsed: elapsed, timeConstant: configuration.speedSmoothingSeconds)
        let previousSpeed = filteredSpeed ?? measuredSpeed
        let nextSpeed = previousSpeed + (measuredSpeed - previousSpeed) * speedAlpha
        filteredSpeed = max(nextSpeed, 0)

        updateBearingTracking(speedMetersPerSecond: filteredSpeed ?? 0)
        let measuredBearing = reliableBearing(sample, derivedBearing: derivedMotion.bearing)
        if lastTravelBearing == nil, let fallbackBearing = sample.fallbackBearingDegrees {
            lastTravelBearing = Self.normalizedBearing(fallbackBearing)
        }
        if bearingTrackingActive, let measuredBearing {
            // Enter heading-up progressively as motion becomes trustworthy.
            // Snapping straight to the first valid course can rotate the map
            // violently when a rider leaves lights or starts a ride facing south.
            let previous = smoothedBearing ?? lastTravelBearing ?? 0
            let alpha = smoothingAlpha(elapsed: elapsed, timeConstant: configuration.bearingSmoothingSeconds)
            let requestedDelta = Self.shortestArcDelta(from: previous, to: measuredBearing) * alpha
            let boundedDelta = min(max(requestedDelta, -configuration.maximumBearingStepDegrees), configuration.maximumBearingStepDegrees)
            smoothedBearing = Self.normalizedBearing(previous + boundedDelta)
            lastTravelBearing = smoothedBearing
        }

        // Do not expose an unfiltered course while speed hysteresis is still
        // deciding whether the rider is moving. Until tracking engages, north
        // is calmer and safer than a single noisy derived bearing.
        let travelBearing = lastTravelBearing ?? 0
        let speed = filteredSpeed ?? 0
        let speedKmh = speed * 3.6
        let lookahead = max(speed * configuration.horizonSeconds, configuration.minimumLookaheadMeters)
        let pitch = cameraPitch(speedKmh: speedKmh, mode: sample.mode)
        let viewportScale = min(max(800 / max(sample.viewportHeightPoints, 320), 0.82), 1.48)
        let pitchScale = 1 - pitch / 220
        let distanceMultiplier = sample.mode == .immersive ? 1.38 : 2.0
        let cameraDistance = min(
            max(lookahead * distanceMultiplier * viewportScale * pitchScale, configuration.minimumCameraDistanceMeters),
            configuration.maximumCameraDistanceMeters
        )
        let movingOffsetProgress = min(max(speedKmh / 18, 0), 1)
        let offsetProgress: Double = switch sample.mode {
        case .immersive: max(movingOffsetProgress, 0.58)
        case .headingUp: movingOffsetProgress
        case .northUp: 0
        }
        let offsetMultiplier: Double = switch sample.mode {
        case .immersive: 0.72
        case .headingUp: 0.42
        case .northUp: 0.0
        }
        let center = Self.project(
            sample.coordinate,
            distanceMeters: lookahead * offsetMultiplier * offsetProgress,
            bearingDegrees: travelBearing
        )
        let bearing = sample.mode == .northUp ? 0 : travelBearing

        lastCoordinate = sample.coordinate
        lastTimestamp = sample.timestamp

        return LiveRideCameraState(
            center: center,
            cameraDistanceMeters: cameraDistance,
            bearingDegrees: bearing,
            travelBearingDegrees: travelBearing,
            pitchDegrees: pitch,
            lookaheadMeters: lookahead,
            filteredSpeedMetersPerSecond: speed,
            holdsBearing: !bearingTrackingActive,
            animationDuration: sample.reduceMotion ? 0 : min(max(elapsed * 0.95, 0.7), 1.05)
        )
    }

    static func shortestArcDelta(from: Double, to: Double) -> Double {
        var delta = (to - from + 540).truncatingRemainder(dividingBy: 360) - 180
        if delta <= -180 { delta += 360 }
        return delta
    }

    static func bearing(from: Coordinate, to: Coordinate) -> Double {
        let startLatitude = from.latitude * .pi / 180
        let endLatitude = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) -
            sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)
        return normalizedBearing(atan2(y, x) * 180 / .pi)
    }

    private mutating func updateBearingTracking(speedMetersPerSecond: Double) {
        let speedKmh = speedMetersPerSecond * 3.6
        if bearingTrackingActive {
            if speedKmh < configuration.bearingReleaseSpeedKmh { bearingTrackingActive = false }
        } else if speedKmh >= configuration.bearingEngageSpeedKmh {
            bearingTrackingActive = true
        }
    }

    private func reliableSpeed(_ sample: LiveRideCameraSample, derivedSpeed: Double?) -> Double {
        let sensorIsUsable = sample.speedMetersPerSecond >= 0 &&
            (sample.speedAccuracyMetersPerSecond.map { $0 >= 0 && $0 <= 4 } ?? true)
        if sensorIsUsable { return sample.speedMetersPerSecond }
        return derivedSpeed ?? max(sample.speedMetersPerSecond, 0)
    }

    private func reliableBearing(_ sample: LiveRideCameraSample, derivedBearing: Double?) -> Double? {
        let courseIsUsable = sample.courseDegrees >= 0 && sample.courseDegrees <= 360 &&
            (sample.courseAccuracyDegrees.map { $0 >= 0 && $0 <= 35 } ?? false)
        return courseIsUsable ? Self.normalizedBearing(sample.courseDegrees) : derivedBearing
    }

    private func derivedMotion(to coordinate: Coordinate, elapsed: TimeInterval) -> (speed: Double?, bearing: Double?) {
        guard let lastCoordinate else { return (nil, nil) }
        let distance = Self.distanceMeters(from: lastCoordinate, to: coordinate)
        guard distance >= 2 else { return (elapsed > 0 ? distance / elapsed : nil, nil) }
        return (elapsed > 0 ? distance / elapsed : nil, Self.bearing(from: lastCoordinate, to: coordinate))
    }

    private func elapsedSeconds(to timestamp: Date) -> TimeInterval {
        guard let lastTimestamp else { return 1 }
        let elapsed = timestamp.timeIntervalSince(lastTimestamp)
        return elapsed > 0 && elapsed < 10 ? elapsed : 1
    }

    private func smoothingAlpha(elapsed: TimeInterval, timeConstant: TimeInterval) -> Double {
        1 - exp(-elapsed / max(timeConstant, 0.01))
    }

    private func cameraPitch(speedKmh: Double, mode: LiveRideCameraMode) -> Double {
        switch mode {
        case .immersive:
            // Immersive is a persistent rider-eye camera, including while
            // waiting at lights. Speed adds a little more road horizon rather
            // than dropping the map back to a top-down view at rest.
            return min(56 + 16 * (1 - exp(-max(speedKmh, 0) / 28)), 72)
        case .headingUp:
            guard speedKmh >= 1.5 else { return 0 }
            return min(46 * (1 - exp(-speedKmh / 24)), 46)
        case .northUp:
            return 0
        }
    }

    private static func project(_ coordinate: Coordinate, distanceMeters: Double, bearingDegrees: Double) -> Coordinate {
        let earthRadiusMeters = 6_371_000.0
        let angularDistance = distanceMeters / earthRadiusMeters
        let bearing = bearingDegrees * .pi / 180
        let startLatitude = coordinate.latitude * .pi / 180
        let startLongitude = coordinate.longitude * .pi / 180
        let endLatitude = asin(
            sin(startLatitude) * cos(angularDistance) +
                cos(startLatitude) * sin(angularDistance) * cos(bearing)
        )
        let endLongitude = startLongitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(startLatitude),
            cos(angularDistance) - sin(startLatitude) * sin(endLatitude)
        )
        return Coordinate(
            latitude: endLatitude * 180 / .pi,
            longitude: endLongitude * 180 / .pi
        )
    }

    private static func distanceMeters(from: Coordinate, to: Coordinate) -> Double {
        let latitudeScale = 111_320.0
        let longitudeScale = latitudeScale * cos(from.latitude * .pi / 180)
        let north = (to.latitude - from.latitude) * latitudeScale
        let east = (to.longitude - from.longitude) * longitudeScale
        return hypot(north, east)
    }

    private static func normalizedBearing(_ bearing: Double) -> Double {
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}
