import SwiftUI

// MARK: - StatCard
//
// A single metric: label, large value, unit, optional trend. The value uses the
// rounded display face so numbers feel like instrument readouts (Tesla/Strava).

struct StatCard: View {
    let label: String
    let value: String
    var unit: String? = nil
    var trend: Trend? = nil
    var systemImage: String? = nil

    enum Trend: Equatable {
        case up(String)
        case down(String)
        case neutral(String)

        var text: String {
            switch self {
            case .up(let t), .down(let t), .neutral(let t): t
            }
        }
        var symbol: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .neutral: "minus"
            }
        }
        var color: Color {
            switch self {
            case .up: .mlSuccess
            case .down: .mlDanger
            case .neutral: .mlTextSecondary
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlAccent)
                }
                Text(label)
                    .mlKicker()
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(MLFont.display)
                    .foregroundStyle(Color.mlTextPrimary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                }
            }

            if let trend {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: trend.symbol)
                    Text(trend.text)
                }
                .font(MLFont.caption)
                .foregroundStyle(trend.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
        .accessibilityValue(trend?.text ?? "")
    }
}

// MARK: - Previews

#Preview("StatCard — states") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                StatCard(label: "Distance", value: "84.3", unit: "km",
                         trend: .up("12% vs last week"), systemImage: "map")
                StatCard(label: "Flow", value: "87", trend: .up("new best"),
                         systemImage: "waveform.path.ecg")
            }
            HStack(spacing: Spacing.md) {
                StatCard(label: "Elevation", value: "1,240", unit: "m",
                         trend: .down("−4%"), systemImage: "mountain.2")
                StatCard(label: "Moving Time", value: "2h 12m",
                         systemImage: "clock")
            }
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
