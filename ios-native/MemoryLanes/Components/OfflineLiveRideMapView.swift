@preconcurrency import MapLibre
import SwiftUI

/// Live navigation surface backed by the same MapLibre cache as downloaded
/// offline areas. Route guidance and recording remain independent of rendering.
struct OfflineLiveRideMapView: UIViewRepresentable {
    let recordedRoute: [Coordinate]
    let guideRoute: [Coordinate]
    let latestPoint: RecordingPoint?
    let liveRiders: [GroupLiveRider]
    let cameraMode: LiveRideCameraMode
    let reduceMotion: Bool
    @Binding var followsCamera: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapLibreOfflineMapStore.styleURL)
        mapView.delegate = context.coordinator
        mapView.compassView.isHidden = true
        mapView.scaleBar.isHidden = true
        mapView.logoViewPosition = .bottomLeft
        mapView.attributionButtonPosition = .bottomLeft
        mapView.allowsRotating = true
        mapView.allowsTilting = true
        context.coordinator.updateContent(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateContent(on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: OfflineLiveRideMapView

        private var cameraController = LiveRideCameraController()
        private var lastCameraState: LiveRideCameraState?
        private var lastSampleTimestamp: Date?
        private var lastMode: LiveRideCameraMode?
        private var lastReduceMotion: Bool?
        private var recordedSignature = OfflineRouteSignature.empty
        private var guideSignature = OfflineRouteSignature.empty
        private var routeAnnotations: [MLNShape] = []
        private var riderAnnotation: OfflineRiderAnnotation?
        private var groupAnnotations: [UUID: OfflineGroupRiderAnnotation] = [:]
        private var mapFinishedLoading = false
        private var didFrameInitialContent = false
        private var didApplyCamera = false
        private var applyingCameraProgrammatically = false

        init(parent: OfflineLiveRideMapView) {
            self.parent = parent
        }

        func mapViewWillStartLoadingMap(_ mapView: MLNMapView) {
            mapFinishedLoading = false
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            mapFinishedLoading = true
            updateContent(on: mapView)
        }

        func updateContent(on mapView: MLNMapView) {
            guard mapFinishedLoading else { return }
            updateRoutes(on: mapView)
            updateGroupRiders(on: mapView)
            frameInitialContentIfNeeded(on: mapView)
            updateRider(on: mapView)
        }

        func mapView(
            _ mapView: MLNMapView,
            strokeColorForShapeAnnotation annotation: MLNShape
        ) -> UIColor {
            switch annotation.title ?? "" {
            case OfflineOverlayKind.guideCasing.rawValue:
                UIColor.black.withAlphaComponent(0.72)
            case OfflineOverlayKind.guide.rawValue:
                UIColor(Color.mlAccent)
            default:
                UIColor(Color.mlTextSecondary).withAlphaComponent(0.58)
            }
        }

        func mapView(
            _ mapView: MLNMapView,
            lineWidthForPolylineAnnotation annotation: MLNPolyline
        ) -> CGFloat {
            switch annotation.title ?? "" {
            case OfflineOverlayKind.guideCasing.rawValue: 13
            case OfflineOverlayKind.guide.rawValue: 8
            default: 5
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is OfflineRiderAnnotation {
                let identifier = "offline-live-rider"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? OfflineRiderPuckView)
                    ?? OfflineRiderPuckView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                return view
            }
            if annotation is OfflineGroupRiderAnnotation {
                let identifier = "offline-group-rider"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? OfflineGroupRiderView)
                    ?? OfflineGroupRiderView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                return view
            }
            return nil
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            guard !applyingCameraProgrammatically else { return }
            let gestureHosts: [UIView] = [mapView] + mapView.subviews
            var gestures: [UIGestureRecognizer] = []
            for view in gestureHosts {
                gestures.append(contentsOf: view.gestureRecognizers ?? [])
            }
            let isRiderGesture = gestures.contains { gesture in
                gesture.state == .began || gesture.state == .changed
            }
            if isRiderGesture, parent.followsCamera {
                parent.followsCamera = false
            }
        }

        private func updateRoutes(on mapView: MLNMapView) {
            let nextRecorded = OfflineRouteSignature(parent.recordedRoute)
            let nextGuide = OfflineRouteSignature(parent.guideRoute)
            guard nextRecorded != recordedSignature || nextGuide != guideSignature else { return }

            mapView.removeAnnotations(routeAnnotations)
            routeAnnotations.removeAll(keepingCapacity: true)
            if parent.recordedRoute.count > 1 {
                routeAnnotations.append(polyline(parent.recordedRoute, kind: .recorded))
            }
            if parent.guideRoute.count > 1 {
                routeAnnotations.append(polyline(parent.guideRoute, kind: .guideCasing))
                routeAnnotations.append(polyline(parent.guideRoute, kind: .guide))
            }
            mapView.addAnnotations(routeAnnotations)
            recordedSignature = nextRecorded
            guideSignature = nextGuide
        }

        private func polyline(_ coordinates: [Coordinate], kind: OfflineOverlayKind) -> MLNPolyline {
            let line = MLNPolyline(coordinates: coordinates.clCoordinates, count: UInt(coordinates.count))
            line.title = kind.rawValue
            return line
        }

        private func updateRider(on mapView: MLNMapView) {
            guard let point = parent.latestPoint else { return }
            if riderAnnotation == nil {
                let annotation = OfflineRiderAnnotation()
                riderAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
            riderAnnotation?.coordinate = point.coordinate.clCoordinate

            let shouldRecalculate = lastSampleTimestamp != point.timestamp
                || lastMode != parent.cameraMode
                || lastReduceMotion != parent.reduceMotion
            if shouldRecalculate {
                lastCameraState = cameraController.update(
                    LiveRideCameraSample(
                        coordinate: point.coordinate,
                        timestamp: point.timestamp,
                        speedMetersPerSecond: point.speedMetersPerSecond,
                        speedAccuracyMetersPerSecond: point.speedAccuracyMetersPerSecond,
                        courseDegrees: point.courseDegrees,
                        courseAccuracyDegrees: point.courseAccuracyDegrees,
                        fallbackBearingDegrees: guideBearing,
                        viewportHeightPoints: mapView.bounds.height,
                        mode: parent.cameraMode,
                        reduceMotion: parent.reduceMotion
                    )
                )
                lastSampleTimestamp = point.timestamp
                lastMode = parent.cameraMode
                lastReduceMotion = parent.reduceMotion
            }

            guard let cameraState = lastCameraState else { return }
            if let riderAnnotation,
               let riderView = mapView.view(for: riderAnnotation) as? OfflineRiderPuckView {
                let relativeHeading = LiveRideCameraController.shortestArcDelta(
                    from: cameraState.bearingDegrees,
                    to: cameraState.travelBearingDegrees
                )
                riderView.setRelativeHeading(relativeHeading)
            }
            guard parent.followsCamera else { return }
            apply(cameraState, to: mapView)
        }

        private var guideBearing: Double? {
            guard let start = parent.guideRoute.first,
                  let end = parent.guideRoute.dropFirst().first else { return nil }
            return LiveRideCameraController.bearing(from: start, to: end)
        }

        private func updateGroupRiders(on mapView: MLNMapView) {
            let incomingIDs = Set(parent.liveRiders.map(\.id))
            let removedIDs = Set(groupAnnotations.keys).subtracting(incomingIDs)
            let removed = removedIDs.compactMap { groupAnnotations.removeValue(forKey: $0) }
            mapView.removeAnnotations(removed)

            for rider in parent.liveRiders {
                if let annotation = groupAnnotations[rider.id] {
                    annotation.update(with: rider)
                } else {
                    let annotation = OfflineGroupRiderAnnotation(rider: rider)
                    groupAnnotations[rider.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        private func frameInitialContentIfNeeded(on mapView: MLNMapView) {
            guard !didFrameInitialContent, parent.latestPoint == nil else { return }
            let route = parent.recordedRoute.isEmpty
                ? parent.guideRoute
                : parent.recordedRoute + parent.guideRoute
            guard route.count > 1 else { return }
            let latitudes = route.map(\.latitude)
            let longitudes = route.map(\.longitude)
            guard let south = latitudes.min(), let north = latitudes.max(),
                  let west = longitudes.min(), let east = longitudes.max() else { return }
            didFrameInitialContent = true
            mapView.setVisibleCoordinateBounds(
                MLNCoordinateBounds(
                    sw: .init(latitude: south, longitude: west),
                    ne: .init(latitude: north, longitude: east)
                ),
                edgePadding: UIEdgeInsets(top: 120, left: 36, bottom: 260, right: 36),
                animated: false,
                completionHandler: nil
            )
        }

        private func apply(_ state: LiveRideCameraState, to mapView: MLNMapView) {
            let camera = MLNMapCamera(
                lookingAtCenter: state.center.clCoordinate,
                acrossDistance: state.cameraDistanceMeters,
                pitch: state.pitchDegrees,
                heading: state.bearingDegrees
            )
            applyingCameraProgrammatically = true
            defer { applyingCameraProgrammatically = false }
            if !didApplyCamera || state.animationDuration == 0 {
                mapView.setCamera(camera, animated: false)
                didApplyCamera = true
                return
            }
            UIView.animate(
                withDuration: state.animationDuration,
                delay: 0,
                usingSpringWithDamping: 0.94,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                mapView.camera = camera
            }
        }
    }
}

private enum OfflineOverlayKind: String {
    case guide
    case guideCasing
    case recorded
}

private struct OfflineRouteSignature: Equatable {
    let count: Int
    let first: Coordinate?
    let last: Coordinate?

    static let empty = OfflineRouteSignature(count: 0, first: nil, last: nil)

    init(_ route: [Coordinate]) {
        count = route.count
        first = route.first
        last = route.last
    }

    private init(count: Int, first: Coordinate?, last: Coordinate?) {
        self.count = count
        self.first = first
        self.last = last
    }
}

private final class OfflineRiderAnnotation: MLNPointAnnotation {}

private final class OfflineGroupRiderAnnotation: MLNPointAnnotation {
    let id: UUID

    init(rider: GroupLiveRider) {
        id = rider.id
        super.init()
        update(with: rider)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(with rider: GroupLiveRider) {
        coordinate = CLLocationCoordinate2D(latitude: rider.latitude, longitude: rider.longitude)
        title = rider.name
        if let speedKmH = rider.speedKmH {
            subtitle = "\(Int(speedKmH.rounded())) km/h"
        } else {
            subtitle = "Live with your group"
        }
    }
}

private final class OfflineRiderPuckView: MLNAnnotationView {
    private let arrow = UIImageView(image: UIImage(systemName: "location.north.fill"))

    override init(annotation: MLNAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 42, height: 42)
        centerOffset = CGVector(dx: 0, dy: -3)

        let halo = UIView(frame: bounds)
        halo.backgroundColor = UIColor(Color.mlAccent).withAlphaComponent(0.2)
        halo.layer.cornerRadius = bounds.width / 2
        addSubview(halo)

        let core = UIView(frame: CGRect(x: 8, y: 8, width: 26, height: 26))
        core.backgroundColor = UIColor(Color.mlAccent)
        core.layer.cornerRadius = 13
        core.layer.borderWidth = 3
        core.layer.borderColor = UIColor.white.cgColor
        core.layer.shadowColor = UIColor.black.cgColor
        core.layer.shadowOpacity = 0.32
        core.layer.shadowRadius = 4
        core.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(core)

        arrow.frame = core.bounds.insetBy(dx: 6, dy: 6)
        arrow.contentMode = .scaleAspectFit
        arrow.tintColor = UIColor(Color.mlOnAccent)
        core.addSubview(arrow)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setRelativeHeading(_ degrees: Double) {
        arrow.transform = CGAffineTransform(rotationAngle: degrees * .pi / 180)
    }
}

private final class OfflineGroupRiderView: MLNAnnotationView {
    override init(annotation: MLNAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        centerOffset = CGVector(dx: 0, dy: -3)
        backgroundColor = UIColor(Color.mlInfo)
        layer.cornerRadius = 19
        layer.borderWidth = 3
        layer.borderColor = UIColor(Color.mlOnAccent).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let image = UIImageView(image: UIImage(systemName: "person.fill"))
        image.frame = bounds.insetBy(dx: 10, dy: 10)
        image.contentMode = .scaleAspectFit
        image.tintColor = UIColor(Color.mlOnAccent)
        addSubview(image)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
