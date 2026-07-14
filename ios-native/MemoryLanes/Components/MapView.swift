import SwiftUI
import MapKit

// MARK: - RouteThumbnail
//
// A small, non-interactive map that draws a ride's route in the accent colour.
// Used inside RideCards. Interaction is disabled so it reads as an image and the
// whole card stays a single tap target.

struct RouteThumbnail: View {
    let route: [Coordinate]

    private var coordinates: [CLLocationCoordinate2D] { route.clCoordinates }

    var body: some View {
        Map(initialPosition: .region(RouteGeometry.region(for: route, paddingFactor: 1.35)),
            interactionModes: []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.mlAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - MapView
//
// The full-bleed hero map for the Ride Detail screen. Route drawn thick in the
// accent colour, start/end annotations, a gradient fade at the bottom edge so
// the map dissolves into the sheet below it.

struct MLMapView: View {
    let route: [Coordinate]
    var fadeColor: Color = .mlBackground
    var replayIndex: Int? = nil
    var replayCoordinate: Coordinate? = nil
    var completedRoute: [Coordinate] = []
    var guideRoute: [Coordinate] = []
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] { route.clCoordinates }
    private var guideCoordinates: [CLLocationCoordinate2D] { guideRoute.clCoordinates }
    private var framingRoute: [Coordinate] {
        route.isEmpty ? guideRoute : route + guideRoute
    }
    private var replayMapCoordinate: CLLocationCoordinate2D? {
        if let replayCoordinate {
            return replayCoordinate.clCoordinate
        }
        guard let replayIndex, route.indices.contains(replayIndex) else { return nil }
        return route[replayIndex].clCoordinate
    }
    private var completedCoordinates: [CLLocationCoordinate2D] {
        if completedRoute.count > 1 {
            return completedRoute.clCoordinates
        }
        guard let replayIndex, replayIndex > 0 else { return [] }
        return Array(route.prefix(min(replayIndex + 1, route.count))).clCoordinates
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if guideCoordinates.count > 1 {
                MapPolyline(coordinates: guideCoordinates)
                    .stroke(Color.mlInfo.opacity(0.78), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [9, 8]))
            }
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.mlAccent.opacity(replayMapCoordinate == nil ? 1 : 0.32), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if completedCoordinates.count > 1 {
                MapPolyline(coordinates: completedCoordinates)
                    .stroke(Color.mlAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    endpointDot(fill: Color.mlAccent)
                }
            }
            if let end = coordinates.last, coordinates.count > 1 {
                Annotation("Finish", coordinate: end) {
                    endpointDot(fill: Color.mlSurfaceElevated, ring: Color.mlAccent)
                }
            }
            if let replayMapCoordinate {
                Annotation("Replay position", coordinate: replayMapCoordinate) {
                    replayDot
                }
            }
        }
        .onAppear {
            cameraPosition = .region(RouteGeometry.region(for: framingRoute))
        }
        .onChange(of: replayCoordinate) { _, coordinate in
            guard let coordinate else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(RouteGeometry.replayRegion(centeredOn: coordinate))
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .overlay(alignment: .bottom) {
            LinearGradient.mlMapFade(fadeColor)
                .frame(height: 120)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Route map")
    }

    private func endpointDot(fill: Color, ring: Color = .white) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(ring, lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    private var replayDot: some View {
        ZStack {
            Circle()
                .fill(Color.mlAccent.opacity(0.22))
                .frame(width: 34, height: 34)
            Circle()
                .fill(Color.mlAccent)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }
}

// MARK: - Route geometry helpers

enum RouteGeometry {
    /// A region that frames the whole route with a little breathing room.
    static func region(for coordinates: [Coordinate], paddingFactor: Double = 1.4) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: .init(latitude: 37.0, longitude: -121.5),
                span: .init(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * paddingFactor, 0.005),
            longitudeDelta: max((maxLon - minLon) * paddingFactor, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    static func replayRegion(centeredOn coordinate: Coordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate.clCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    }
}

// MARK: - Previews

#Preview("RouteThumbnail") {
    RouteThumbnail(route: SampleData.ridgeRoute)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding()
        .background(Color.mlBackground)
        .preferredColorScheme(.dark)
}

#Preview("Hero MapView") {
    MLMapView(route: SampleData.ridgeRoute)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
}
