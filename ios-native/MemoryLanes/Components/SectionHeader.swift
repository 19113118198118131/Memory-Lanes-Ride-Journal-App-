import SwiftUI

// MARK: - SectionHeader
//
// A title with an optional right-aligned action. Used to open every list
// section so headers are identical across screens.

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(MLFont.title2)
                .foregroundStyle(Color.mlTextPrimary)
            Spacer(minLength: Spacing.sm)
            if let actionTitle, let action {
                Button {
                    Haptics.selection()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlAccent)
                }
                .mlHitTarget()
                .accessibilityLabel("\(actionTitle), \(title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - SegmentedMetric
//
// A horizontal row of 3–4 stats separated by hairline dividers — the classic
// distance / time / elevation strip under a ride's title.

struct SegmentedMetric: View {
    struct Item: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
        let label: String
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(item.value)
                            .font(MLFont.displaySmall)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text(item.unit)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Text(item.label)
                        .mlKicker()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.label): \(item.value) \(item.unit)")

                if index < items.count - 1 {
                    Rectangle()
                        .fill(Color.mlHairline)
                        .frame(width: Layout.hairline, height: 28)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Previews

#Preview("SectionHeader + SegmentedMetric") {
    VStack(spacing: Spacing.lg) {
        SectionHeader(title: "Recent Rides", actionTitle: "See all") {}
        SegmentedMetric(items: [
            .init(value: "84.3", unit: "km", label: "Distance"),
            .init(value: "2h 12m", unit: "", label: "Time"),
            .init(value: "1,240", unit: "m", label: "Ascent")
        ])
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
