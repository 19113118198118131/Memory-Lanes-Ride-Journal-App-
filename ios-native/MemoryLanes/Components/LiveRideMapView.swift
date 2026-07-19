import MapKit
import SwiftUI

struct LiveRideMapView: UIViewRepresentable {
    let recordedRoute: [Coordinate]
    let guideRoute: [Coordinate]
    let latestPoint: RecordingPoint?
    let liveRiders: [GroupLiveRider]
    let cameraMode: LiveRideCameraMode
    let reduceMotion: Bool
    @Binding var followsCamera: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 180,
            maxCenterCoordinateDistance: 3_000
        )
        context.coordinator.configureMap(mapView, colorScheme: colorScheme)
        context.coordinator.updateOverlays(on: mapView, recorded: recordedRoute, guide: guideRoute)
        context.coordinator.frameInitialContent(on: mapView, recorded: recordedRoute, guide: guideRoute)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureMap(mapView, colorScheme: colorScheme)
        context.coordinator.updateOverlays(on: mapView, recorded: recordedRoute, guide: guideRoute)
        context.coordinator.updateGroupRiders(liveRiders, on: mapView)
        context.coordinator.update(point: latestPoint, on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LiveRideMapView

        private var cameraController = LiveRideCameraController()
        private let riderAnnotation = RiderAnnotation()
        private var lastCameraState: LiveRideCameraState?
        private var lastSampleTimestamp: Date?
        private var lastMode: LiveRideCameraMode?
        private var lastReduceMotion: Bool?
        private var recordedSignature = RouteSignature.empty
        private var guideSignature = RouteSignature.empty
        private var renderedOverlays: [MKOverlay] = []
        private var groupRiderAnnotations: [UUID: GroupRiderAnnotation] = [:]
        private var didAddRiderAnnotation = false
        private var didApplyCamera = false
        private var configuredColorScheme: ColorScheme?

        init(parent: LiveRideMapView) {
            self.parent = parent
        }

        func configureMap(_ mapView: MKMapView, colorScheme: ColorScheme) {
            guard configuredColorScheme != colorScheme else { return }
            configuredColorScheme = colorScheme
            mapView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            let configuration = MKStandardMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            configuration.showsTraffic = false
            configuration.emphasisStyle = .default
            mapView.preferredConfiguration = configuration
        }

        func frameInitialContent(on mapView: MKMapView, recorded: [Coordinate], guide: [Coordinate]) {
            let framingRoute = recorded.isEmpty ? guide : recorded + guide
            guard framingRoute.count > 1 else {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: -36.85, longitude: 174.76),
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                    ),
                    animated: false
                )
                return
            }
            let polyline = MKPolyline(coordinates: framingRoute.clCoordinates, count: framingRoute.count)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 120, left: 36, bottom: 260, right: 36),
                animated: false
            )
        }

        func updateOverlays(on mapView: MKMapView, recorded: [Coordinate], guide: [Coordinate]) {
            let nextRecordedSignature = RouteSignature(recorded)
            let nextGuideSignature = RouteSignature(guide)
            guard nextRecordedSignature != recordedSignature || nextGuideSignature != guideSignature else { return }

            mapView.removeOverlays(renderedOverlays)
            renderedOverlays.removeAll(keepingCapacity: true)

            if recorded.count > 1 {
                let overlay = MKPolyline(coordinates: recorded.clCoordinates, count: recorded.count)
                overlay.title = OverlayKind.recorded.rawValue
                renderedOverlays.append(overlay)
            }
            if guide.count > 1 {
                let overlay = MKPolyline(coordinates: guide.clCoordinates, count: guide.count)
                overlay.title = OverlayKind.guide.rawValue
                renderedOverlays.append(overlay)
            }
            mapView.addOverlays(renderedOverlays, level: .aboveRoads)
            recordedSignature = nextRecordedSignature
            guideSignature = nextGuideSignature
        }

        func update(point: RecordingPoint?, on mapView: MKMapView) {
            guard let point else { return }
            if !didAddRiderAnnotation {
                mapView.addAnnotation(riderAnnotation)
                didAddRiderAnnotation = true
            }
            riderAnnotation.coordinate = point.coordinate.clCoordinate

            let shouldRecalculate = lastSampleTimestamp != point.timestamp ||
                lastMode != parent.cameraMode ||
                lastReduceMotion != parent.reduceMotion
            if shouldRecalculate {
                lastCameraState = cameraController.update(
                    LiveRideCameraSample(
                        coordinate: point.coordinate,
                        timestamp: point.timestamp,
                        speedMetersPerSecond: point.speedMetersPerSecond,
                        speedAccuracyMetersPerSecond: point.speedAccuracyMetersPerSecond,
                        courseDegrees: point.courseDegrees,
                        courseAccuracyDegrees: point.courseAccuracyDegrees,
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
            updatePuckHeading(cameraState, on: mapView)
            guard parent.followsCamera else { return }
            apply(cameraState, to: mapView)
        }

        func updateGroupRiders(_ riders: [GroupLiveRider], on mapView: MKMapView) {
            let incomingIDs = Set(riders.map(\.id))
            let removedIDs = Set(groupRiderAnnotations.keys).subtracting(incomingIDs)
            let removedAnnotations = removedIDs.compactMap { groupRiderAnnotations.removeValue(forKey: $0) }
            mapView.removeAnnotations(removedAnnotations)

            for rider in riders {
                if let annotation = groupRiderAnnotations[rider.id] {
                    annotation.update(with: rider)
                } else {
                    let annotation = GroupRiderAnnotation(rider: rider)
                    groupRiderAnnotations[rider.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if polyline.title == OverlayKind.guide.rawValue {
                renderer.strokeColor = UIColor(Color.mlInfo)
                renderer.lineWidth = 7
            } else {
                renderer.strokeColor = UIColor(Color.mlAccent).withAlphaComponent(0.68)
                renderer.lineWidth = 4
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation === riderAnnotation {
                let identifier = "live-rider"
                if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RiderPuckAnnotationView {
                    reused.annotation = annotation
                    return reused
                }
                return RiderPuckAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }

            guard annotation is GroupRiderAnnotation else { return nil }
            let identifier = "group-live-rider"
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.canShowCallout = true
            marker.markerTintColor = UIColor(Color.mlInfo)
            marker.glyphTintColor = UIColor(Color.mlOnAccent)
            marker.glyphImage = UIImage(systemName: "person.fill")
            marker.displayPriority = .required
            marker.collisionMode = .circle
            return marker
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let gestureHosts: [UIView] = [mapView] + mapView.subviews
            let gestures: [UIGestureRecognizer] = gestureHosts.reduce(into: []) { result, view in
                result.append(contentsOf: view.gestureRecognizers ?? [])
            }
            let riderIsMovingMap = gestures.contains { gesture in
                gesture.state == .began || gesture.state == .changed
            }
            if riderIsMovingMap, parent.followsCamera {
                parent.followsCamera = false
            }
        }

        private func apply(_ state: LiveRideCameraState, to mapView: MKMapView) {
            let camera = MKMapCamera(
                lookingAtCenter: state.center.clCoordinate,
                fromDistance: state.cameraDistanceMeters,
                pitch: state.pitchDegrees,
                heading: state.bearingDegrees
            )
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

        private func updatePuckHeading(_ state: LiveRideCameraState, on mapView: MKMapView) {
            guard let view = mapView.view(for: riderAnnotation) as? RiderPuckAnnotationView else { return }
            let relativeHeading = LiveRideCameraController.shortestArcDelta(
                from: state.bearingDegrees,
                to: state.travelBearingDegrees
            )
            view.setRelativeHeading(relativeHeading)
        }
    }
}

private enum OverlayKind: String {
    case guide
    case recorded
}

private struct RouteSignature: Equatable {
    let count: Int
    let first: Coordinate?
    let last: Coordinate?

    static let empty = RouteSignature(count: 0, first: nil, last: nil)

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

private final class RiderAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D(latitude: -36.85, longitude: 174.76)
}

private final class GroupRiderAnnotation: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(rider: GroupLiveRider) {
        id = rider.id
        coordinate = CLLocationCoordinate2D(latitude: rider.latitude, longitude: rider.longitude)
        title = rider.name
        subtitle = Self.subtitle(for: rider)
    }

    func update(with rider: GroupLiveRider) {
        coordinate = CLLocationCoordinate2D(latitude: rider.latitude, longitude: rider.longitude)
        title = rider.name
        subtitle = Self.subtitle(for: rider)
    }

    private static func subtitle(for rider: GroupLiveRider) -> String {
        guard let speedKmH = rider.speedKmH else { return "Live with your group" }
        return "\(Int(speedKmH.rounded())) km/h"
    }
}

private final class RiderPuckAnnotationView: MKAnnotationView {
    private let arrow = UIImageView(image: UIImage(systemName: "location.north.fill"))

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 42, height: 42)
        centerOffset = CGPoint(x: 0, y: -3)
        collisionMode = .circle
        canShowCallout = false

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
