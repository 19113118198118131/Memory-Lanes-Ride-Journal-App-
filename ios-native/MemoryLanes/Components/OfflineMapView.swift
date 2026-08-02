@preconcurrency import MapLibre
import SwiftUI

/// Renders the same style used by offline packs, so MapLibre serves downloaded
/// resources from its local database when the network is unavailable.
struct OfflineMapView: UIViewRepresentable {
    let bounds: OfflineRegionBounds
    var showsUserLocation = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapLibreOfflineMapStore.styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.compassViewPosition = .topRight
        mapView.logoViewPosition = .bottomLeft
        mapView.attributionButtonPosition = .bottomLeft
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.pendingBounds = bounds
        context.coordinator.framePendingBounds(on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var pendingBounds: OfflineRegionBounds?
        private var displayedBounds: OfflineRegionBounds?
        private var mapFinishedLoading = false

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            mapFinishedLoading = true
            framePendingBounds(on: mapView)
        }

        func mapViewWillStartLoadingMap(_ mapView: MLNMapView) {
            mapFinishedLoading = false
        }

        func framePendingBounds(on mapView: MLNMapView) {
            guard mapFinishedLoading,
                  mapView.bounds.width > 0,
                  let bounds = pendingBounds,
                  displayedBounds != bounds else { return }
            displayedBounds = bounds
            let coordinateBounds = MLNCoordinateBounds(
                sw: .init(latitude: bounds.south, longitude: bounds.west),
                ne: .init(latitude: bounds.north, longitude: bounds.east)
            )
            mapView.setVisibleCoordinateBounds(
                coordinateBounds,
                edgePadding: UIEdgeInsets(
                    top: Spacing.lg,
                    left: Spacing.lg,
                    bottom: Layout.offlineMapDetailBottomInset,
                    right: Spacing.lg
                ),
                animated: false,
                completionHandler: nil
            )
        }
    }
}

#Preview {
    OfflineMapView(
        bounds: .centered(
            at: Coordinate(latitude: -36.65, longitude: 174.785),
            sideKilometers: 25
        )
    )
    .frame(height: 360)
    .preferredColorScheme(.dark)
}
