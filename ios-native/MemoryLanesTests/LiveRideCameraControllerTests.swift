import Foundation
import Testing
@testable import MemoryLanes

struct LiveRideCameraControllerTests {
    @Test func shortestArcCrossesNorthWithoutAFullRotation() {
        #expect(LiveRideCameraController.shortestArcDelta(from: 355, to: 5) == 10)
        #expect(LiveRideCameraController.shortestArcDelta(from: 5, to: 355) == -10)
    }

    @Test func bearingFreezesAfterSpeedFallsBelowTheHysteresisFloor() {
        var controller = LiveRideCameraController()
        let start = Date(timeIntervalSince1970: 1_000)
        let moving = controller.update(sample(timestamp: start, speed: 12, course: 82))
        let stopped = controller.update(sample(timestamp: start.addingTimeInterval(8), speed: 0, course: 240))

        #expect(stopped.holdsBearing)
        #expect(stopped.bearingDegrees == moving.bearingDegrees)
        #expect(stopped.pitchDegrees == 0)
    }

    @Test func speedChangesTheTimeHorizonWithoutLeavingCameraBounds() {
        var slowController = LiveRideCameraController()
        var fastController = LiveRideCameraController()
        let date = Date(timeIntervalSince1970: 2_000)

        let slow = slowController.update(sample(timestamp: date, speed: 0, course: -1))
        let fast = fastController.update(sample(timestamp: date, speed: 27.78, course: 40))

        #expect(slow.lookaheadMeters == 120)
        #expect(fast.lookaheadMeters > 490 && fast.lookaheadMeters < 510)
        #expect(fast.cameraDistanceMeters > slow.cameraDistanceMeters)
        #expect(slow.cameraDistanceMeters >= 240)
        #expect(fast.cameraDistanceMeters <= 1_600)
    }

    @Test func reducedMotionForcesAFlatNorthUpCamera() {
        var controller = LiveRideCameraController()
        let result = controller.update(
            sample(
                timestamp: Date(timeIntervalSince1970: 3_000),
                speed: 20,
                course: 145,
                reduceMotion: true
            )
        )

        #expect(result.bearingDegrees == 0)
        #expect(result.pitchDegrees == 0)
        #expect(result.animationDuration == 0)
    }

    @Test func demoRideReplayKeepsCameraMotionBounded() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("assets/demo-ride.gpx"))
        let points = try GPXParser().parse(data: data).points
        #expect(points.count > 500)

        var controller = LiveRideCameraController()
        var previousState: LiveRideCameraState?
        var largestBearingStep = 0.0
        var largestPitchStep = 0.0
        var minimumCameraDistance = Double.greatestFiniteMagnitude
        var maximumCameraDistance = 0.0
        var minimumPitch = Double.greatestFiniteMagnitude
        var maximumPitch = 0.0

        for index in points.indices {
            let previous = index > 0 ? points[index - 1] : nil
            let distance = previous.map { distanceMeters($0.coordinate, points[index].coordinate) } ?? 0
            let elapsed = previous.map { max(points[index].timestamp.timeIntervalSince($0.timestamp), 1) } ?? 1
            let speed = distance / elapsed
            let course = previous.map {
                LiveRideCameraController.bearing(from: $0.coordinate, to: points[index].coordinate)
            } ?? -1
            let state = controller.update(
                LiveRideCameraSample(
                    coordinate: points[index].coordinate,
                    timestamp: points[index].timestamp,
                    speedMetersPerSecond: speed,
                    speedAccuracyMetersPerSecond: 1,
                    courseDegrees: course,
                    courseAccuracyDegrees: course >= 0 ? 5 : nil,
                    viewportHeightPoints: 800,
                    mode: .headingUp,
                    reduceMotion: false
                )
            )

            minimumCameraDistance = min(minimumCameraDistance, state.cameraDistanceMeters)
            maximumCameraDistance = max(maximumCameraDistance, state.cameraDistanceMeters)
            minimumPitch = min(minimumPitch, state.pitchDegrees)
            maximumPitch = max(maximumPitch, state.pitchDegrees)
            if let previousState {
                largestBearingStep = max(
                    largestBearingStep,
                    abs(LiveRideCameraController.shortestArcDelta(
                        from: previousState.bearingDegrees,
                        to: state.bearingDegrees
                    ))
                )
                largestPitchStep = max(largestPitchStep, abs(state.pitchDegrees - previousState.pitchDegrees))
            }
            previousState = state
        }

        #expect(minimumCameraDistance >= 240)
        #expect(maximumCameraDistance <= 1_600)
        #expect(minimumPitch >= 0)
        #expect(maximumPitch <= 50)
        #expect(largestBearingStep <= 28.01)
        #expect(largestPitchStep < 12)
    }

    private func sample(
        timestamp: Date,
        speed: Double,
        course: Double,
        reduceMotion: Bool = false
    ) -> LiveRideCameraSample {
        LiveRideCameraSample(
            coordinate: Coordinate(latitude: -36.85, longitude: 174.76),
            timestamp: timestamp,
            speedMetersPerSecond: speed,
            speedAccuracyMetersPerSecond: 1,
            courseDegrees: course,
            courseAccuracyDegrees: course >= 0 ? 5 : nil,
            viewportHeightPoints: 800,
            mode: .headingUp,
            reduceMotion: reduceMotion
        )
    }

    private func distanceMeters(_ from: Coordinate, _ to: Coordinate) -> Double {
        let latitudeScale = 111_320.0
        let longitudeScale = latitudeScale * cos(from.latitude * .pi / 180)
        return hypot(
            (to.latitude - from.latitude) * latitudeScale,
            (to.longitude - from.longitude) * longitudeScale
        )
    }
}
