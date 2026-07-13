import SwiftUI

// MARK: - RouteShape
//
// Draws a route polyline as a pure SwiftUI `Shape`, normalised to fit its rect.
// Unlike a live MapKit `Map`, a Shape renders reliably through `ImageRenderer`,
// so this is what the exportable ShareCard uses. Aspect ratio is preserved so
// the route keeps its real proportions.

struct RouteShape: Shape {
    let coordinates: [Coordinate]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard coordinates.count > 1 else { return path }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }

        let spanLat = max(maxLat - minLat, 0.0001)
        let spanLon = max(maxLon - minLon, 0.0001)

        // Preserve aspect ratio: fit the larger span, centre the other axis.
        let inset: CGFloat = 24
        let box = rect.insetBy(dx: inset, dy: inset)
        let scale = min(box.width / spanLon, box.height / spanLat)
        let drawW = spanLon * scale
        let drawH = spanLat * scale
        let offsetX = box.minX + (box.width - drawW) / 2
        let offsetY = box.minY + (box.height - drawH) / 2

        func point(_ c: Coordinate) -> CGPoint {
            let x = offsetX + (c.longitude - minLon) * scale
            // Flip latitude: north is up.
            let y = offsetY + (maxLat - c.latitude) * scale
            return CGPoint(x: x, y: y)
        }

        path.move(to: point(coordinates[0]))
        for c in coordinates.dropFirst() {
            path.addLine(to: point(c))
        }
        return path
    }
}

// MARK: - RouteArtwork
//
// The route on a dark canvas with start/end dots — the hero of the share card.

struct RouteArtwork: View {
    let coordinates: [Coordinate]

    var body: some View {
        ZStack {
            Color.mlBackground
            RouteShape(coordinates: coordinates)
                .stroke(Color.mlAccent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.mlAccent.opacity(0.5), radius: 8)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("RouteArtwork") {
    RouteArtwork(coordinates: SampleData.ridgeRoute)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
