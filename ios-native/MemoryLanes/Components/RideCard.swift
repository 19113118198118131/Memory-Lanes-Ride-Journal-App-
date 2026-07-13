import SwiftUI

// MARK: - RideCard
//
// The core list unit: a route thumbnail, title, date, three key stats, and a
// source badge. Everything glanceable without tapping (Strava/Calimoto goal).
// The whole card is one tap target.

struct RideCard: View {
    let ride: Ride
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: {
            Haptics.selection()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                RouteThumbnail(route: ride.routePreview)
                    .frame(height: 148)
                    .overlay(alignment: .topTrailing) {
                        SourceBadge(source: ride.source)
                            .padding(Spacing.sm)
                    }
                    .overlay(alignment: .topLeading) {
                        if let score = ride.flowScore {
                            FlowChip(score: score)
                                .padding(Spacing.sm)
                        }
                    }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ride.title)
                            .font(MLFont.title2)
                            .foregroundStyle(Color.mlTextPrimary)
                            .lineLimit(1)
                        Text(cardSubtitle)
                            .mlCaption()
                    }

                    SegmentedMetric(items: [
                        .init(value: ride.distanceFormatted, unit: "km", label: "Distance"),
                        .init(value: ride.durationFormatted, unit: "", label: "Time"),
                        .init(value: ride.elevationFormatted, unit: "m", label: "Ascent")
                    ])
                }
                .padding(Spacing.md)
            }
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(MLPressableButtonStyle(scale: 0.985))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ride.title), \(ride.distanceFormatted) kilometres, \(ride.durationFormatted), \(cardSubtitle)")
        .accessibilityAddTraits(.isButton)
    }

    private var cardSubtitle: String {
        if let location = ride.locationName {
            return "\(location) · \(ride.relativeDate)"
        }
        return ride.relativeDate
    }
}

// MARK: - SourceBadge

struct SourceBadge: View {
    let source: RideSource

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: source.symbol)
            Text(source.rawValue)
        }
        .font(MLFont.monoSmall)
        .foregroundStyle(Color.mlTextPrimary)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.mlHairline, lineWidth: Layout.hairline))
        .accessibilityLabel("Source: \(source.rawValue)")
    }
}

// MARK: - FlowChip

struct FlowChip: View {
    let score: Int

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "waveform.path.ecg")
            Text("\(score)")
                .font(MLFont.monoSmall.weight(.semibold))
        }
        .font(MLFont.monoSmall)
        .foregroundStyle(Color.mlOnAccent)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
        .background(Color.mlAccent, in: Capsule())
        .accessibilityLabel("Flow score \(score)")
    }
}

// MARK: - Previews

#Preview("RideCard") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            ForEach(SampleData.rides) { ride in
                RideCard(ride: ride)
            }
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
