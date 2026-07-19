import SwiftUI

// MARK: - ShareCard
//
// A beautiful, self-contained summary of a ride, designed to be rendered to an
// image and shared (Strava-style). Fixed aspect so it exports predictably to a
// portrait social format. Drawn over the route so the shape is recognisable.

struct ShareCard: View {
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A vector route (not a live Map) so the card renders reliably through
            // ImageRenderer. Real map tiles can be layered in later via
            // MKMapSnapshotter without changing this view's shape.
            RouteArtwork(coordinates: ride.routePreview)
                .frame(height: 300)
                .overlay(LinearGradient(
                    colors: [.clear, Color.mlBackground.opacity(0.85)],
                    startPoint: .center, endPoint: .bottom
                ))

            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(ride.locationName ?? "Ride").mlKicker()
                    Text(ride.title)
                        .font(MLFont.title)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(ride.dateFormatted)
                        .mlCaption()
                }

                HStack(spacing: 0) {
                    shareStat(ride.distanceFormatted, "km", "Distance")
                    divider
                    shareStat(ride.durationFormatted, "", "Time")
                    divider
                    shareStat(ride.elevationFormatted, "m", "Ascent")
                }

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "location.north.line.fill")
                    Text("MEMORY LANES")
                        .font(MLFont.kicker)
                        .tracking(0)
                    if let flow = ride.flowScore {
                        Spacer()
                        FlowChip(score: flow)
                    }
                }
                .foregroundStyle(Color.mlAccent)
            }
            .padding(Spacing.lg)
        }
        .frame(width: 360, height: 560)
        .background(Color.mlBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func shareStat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(MLFont.display)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(unit).font(MLFont.caption).foregroundStyle(Color.mlTextSecondary)
            }
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Color.mlHairline).frame(width: Layout.hairline, height: 32)
    }
}

// MARK: - Rendering
//
// Renders the card to a `UIImage` off the caller's critical path. `ImageRenderer`
// is main-actor bound, so this stays on the main actor and returns the bitmap.

@MainActor
enum ShareCardRenderer {
    static func image(for ride: Ride, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content:
            ShareCard(ride: ride).environment(\.colorScheme, .dark)
        )
        renderer.scale = scale
        return renderer.uiImage
    }

    static func summaryText(for ride: Ride) -> String {
        var lines = [
            ride.title,
            "\(ride.distanceFormatted) km · \(ride.durationFormatted) · \(ride.elevationFormatted) m ascent"
        ]
        if let location = ride.locationName {
            lines.append(location)
        }
        if let flow = ride.flowScore {
            lines.append("Flow score \(flow)")
        }
        lines.append("Shared from Memory Lanes")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Previews

#Preview("ShareCard") {
    ShareCard(ride: SampleData.hero)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
