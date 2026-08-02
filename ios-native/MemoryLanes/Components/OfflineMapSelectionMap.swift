@preconcurrency import MapLibre
import SwiftUI

struct OfflineMapFocusRequest: Equatable {
    let id: UUID
    let bounds: OfflineRegionBounds
}

struct OfflineMapSelectionMap: UIViewRepresentable {
    @Binding var selectedBounds: OfflineRegionBounds
    let focusRequest: OfflineMapFocusRequest
    let locateRequestID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapLibreOfflineMapStore.styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.compassViewPosition = .topRight
        mapView.logoViewPosition = .bottomLeft
        mapView.attributionButtonPosition = .bottomLeft
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        if mapView.bounds.width > 0, context.coordinator.lastFocusRequestID != focusRequest.id {
            context.coordinator.apply(focusRequest, to: mapView, animated: true)
        }
        if context.coordinator.lastLocateRequestID != locateRequestID {
            context.coordinator.lastLocateRequestID = locateRequestID
            mapView.setUserTrackingMode(.follow, animated: true, completionHandler: nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: OfflineMapSelectionMap
        var lastFocusRequestID: UUID?
        var lastLocateRequestID: UUID?
        private var isApplyingFocus = false

        init(parent: OfflineMapSelectionMap) {
            self.parent = parent
        }

        func apply(_ request: OfflineMapFocusRequest, to mapView: MLNMapView, animated: Bool) {
            lastFocusRequestID = request.id
            isApplyingFocus = true
            let bounds = MLNCoordinateBounds(
                sw: .init(latitude: request.bounds.south, longitude: request.bounds.west),
                ne: .init(latitude: request.bounds.north, longitude: request.bounds.east)
            )
            let rectangle = OfflineMapSelectionLayout.rectangle(in: mapView.bounds.size)
            let insets = UIEdgeInsets(
                top: rectangle.minY,
                left: rectangle.minX,
                bottom: mapView.bounds.height - rectangle.maxY,
                right: mapView.bounds.width - rectangle.maxX
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: insets,
                animated: animated
            ) { [weak self, weak mapView] in
                self?.isApplyingFocus = false
                if let mapView { self?.publishSelection(from: mapView) }
            }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated _: Bool) {
            guard !isApplyingFocus else { return }
            publishSelection(from: mapView)
        }

        private func publishSelection(from mapView: MLNMapView) {
            guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
            let rectangle = OfflineMapSelectionLayout.rectangle(in: mapView.bounds.size)
            let bounds = mapView.convert(rectangle, toCoordinateBoundsFrom: mapView)
            let value = OfflineRegionBounds(
                south: bounds.sw.latitude,
                west: bounds.sw.longitude,
                north: bounds.ne.latitude,
                east: bounds.ne.longitude
            )
            guard value.isValid else { return }
            Task { @MainActor [weak self] in
                self?.parent.selectedBounds = value
            }
        }
    }
}

enum OfflineMapSelectionLayout {
    static func rectangle(in size: CGSize) -> CGRect {
        let side = max(min(size.width - 84, size.height - 108), 120)
        return CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
    }
}
