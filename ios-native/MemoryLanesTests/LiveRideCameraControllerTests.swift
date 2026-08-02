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

        #expect(slow.lookaheadMeters == 110)
        #expect(fast.lookaheadMeters > 550 && fast.lookaheadMeters < 570)
        #expect(fast.cameraDistanceMeters > slow.cameraDistanceMeters)
        #expect(slow.cameraDistanceMeters >= 150)
        #expect(fast.cameraDistanceMeters <= 1_200)
    }

    @Test func immersiveCameraLooksFurtherAheadAndPitchesBelowTheHorizon() {
        let date = Date(timeIntervalSince1970: 2_500)
        var immersiveController = LiveRideCameraController()
        var headingController = LiveRideCameraController()

        let immersive = immersiveController.update(
            sample(timestamp: date, speed: 20, course: 45, mode: .immersive)
        )
        let headingUp = headingController.update(
            sample(timestamp: date, speed: 20, course: 45, mode: .headingUp)
        )

        #expect(immersive.pitchDegrees > headingUp.pitchDegrees)
        #expect(immersive.pitchDegrees >= 54)
        #expect(immersive.cameraDistanceMeters < headingUp.cameraDistanceMeters)
        #expect(immersive.center != sampleCoordinate)
        #expect(immersive.bearingDegrees == headingUp.bearingDegrees)
    }

    @Test func immersiveCameraKeepsRiderPerspectiveAtRest() {
        var controller = LiveRideCameraController()
        let resting = controller.update(
            sample(
                timestamp: Date(timeIntervalSince1970: 2_750),
                speed: 0,
                course: -1,
                mode: .immersive
            )
        )

        #expect(resting.pitchDegrees >= 56)
        #expect(resting.center != sampleCoordinate)
        #expect(resting.cameraDistanceMeters >= 150)
    }

    @Test func plannedRouteOrientsImmersiveCameraBeforeMotionIsReliable() {
        var controller = LiveRideCameraController()
        let resting = controller.update(
            sample(
                timestamp: Date(timeIntervalSince1970: 2_800),
                speed: 0,
                course: -1,
                mode: .immersive,
                fallbackBearing: 132
            )
        )

        #expect(resting.bearingDegrees == 132)
        #expect(resting.travelBearingDegrees == 132)
    }

    @Test func cameraModesCycleBackToImmersive() {
        #expect(LiveRideCameraMode.immersive.next == .headingUp)
        #expect(LiveRideCameraMode.headingUp.next == .northUp)
        #expect(LiveRideCameraMode.northUp.next == .immersive)
    }

    @Test func reducedMotionKeepsRiderPerspectiveWithoutAnimatedCameraTravel() {
        var controller = LiveRideCameraController()
        let result = controller.update(
            sample(
                timestamp: Date(timeIntervalSince1970: 3_000),
                speed: 20,
                course: 145,
                mode: .immersive,
                reduceMotion: true
            )
        )

        #expect(result.bearingDegrees == 28)
        #expect(result.pitchDegrees >= 54)
        #expect(result.animationDuration == 0)
    }

    @Test func destructiveRideActionsReturnOnlyAtLowSpeed() {
        #expect(!LiveRideCockpitPolicy.showsActions(status: .recording, speedMetersPerSecond: 10))
        #expect(LiveRideCockpitPolicy.showsActions(status: .recording, speedMetersPerSecond: 1))
        #expect(LiveRideCockpitPolicy.showsActions(status: .paused, speedMetersPerSecond: 10))
    }

    @Test func activeRideWithPointsOffersFinishAndSaveBeforeClosing() {
        #expect(LiveRideCockpitPolicy.requiresEndRideDecision(status: .recording, pointCount: 12))
        #expect(LiveRideCockpitPolicy.requiresEndRideDecision(status: .paused, pointCount: 12))
        #expect(!LiveRideCockpitPolicy.requiresEndRideDecision(status: .recording, pointCount: 0))
        #expect(!LiveRideCockpitPolicy.requiresEndRideDecision(status: .finished, pointCount: 12))
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
                    fallbackBearingDegrees: nil,
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

        #expect(minimumCameraDistance >= 150)
        #expect(maximumCameraDistance <= 1_200)
        #expect(minimumPitch >= 0)
        #expect(maximumPitch <= 50)
        #expect(largestBearingStep <= 28.01)
        #expect(largestPitchStep < 12)
    }

    private func sample(
        timestamp: Date,
        speed: Double,
        course: Double,
        mode: LiveRideCameraMode = .headingUp,
        reduceMotion: Bool = false,
        fallbackBearing: Double? = nil
    ) -> LiveRideCameraSample {
        LiveRideCameraSample(
            coordinate: sampleCoordinate,
            timestamp: timestamp,
            speedMetersPerSecond: speed,
            speedAccuracyMetersPerSecond: 1,
            courseDegrees: course,
            courseAccuracyDegrees: course >= 0 ? 5 : nil,
            fallbackBearingDegrees: fallbackBearing,
            viewportHeightPoints: 800,
            mode: mode,
            reduceMotion: reduceMotion
        )
    }

    private var sampleCoordinate: Coordinate {
        Coordinate(latitude: -36.85, longitude: 174.76)
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
