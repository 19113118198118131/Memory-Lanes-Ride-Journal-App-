import SwiftUI

// MARK: - MomentRow
//
// A pinned moment in the journal list: symbol, note, and a subtle pin. Kept as a
// row (not a card) so a ride's moments read as a timeline.

struct MomentRow: View {
    let moment: Moment

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: moment.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.mlAccent)
                .frame(width: 40, height: 40)
                .background(Color.mlAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                if !moment.title.isEmpty {
                    Text(moment.title)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Text(moment.note.isEmpty ? "No note yet." : moment.note)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let routeIndex = moment.routeIndex {
                    Text("Pinned at route point \(routeIndex + 1)")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "mappin.and.ellipse")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moment: \(moment.title.isEmpty ? moment.note : moment.title)")
    }
}

// MARK: - WeatherStrip
//
// Historical weather at ride time — temperature, condition, wind — as a compact
// glanceable strip.

struct WeatherStrip: View {
    let weather: Weather

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: weather.symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.mlAccent)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(weather.temperatureFormatted)
                    .font(MLFont.display)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(weather.condition)
                    .mlCaption()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(weather.windFormatted, systemImage: "wind")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                if let precipitation = weather.precipitationFormatted {
                    Label(precipitation, systemImage: "drop.fill")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                Text("At ride time").mlKicker()
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather at ride time: \(weather.temperatureFormatted), \(weather.condition), wind \(weather.windFormatted)")
    }
}

// MARK: - Previews

#Preview("MomentRow + WeatherStrip") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            WeatherStrip(weather: SampleData.weather)
            ForEach(SampleData.moments) { MomentRow(moment: $0) }
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
