import SwiftUI

// MARK: - MLSegmentedControl
//
// A pill segmented control with a spring-animated selection indicator, used to
// switch sections on the Ride Detail screen. We roll our own (rather than the
// system `Picker(.segmented)`) so it inherits the app's surface colours, accent,
// and motion — and to get the matchedGeometry slide.

struct MLSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    Haptics.selection()
                    withAnimation(Motion.spring) { selection = item }
                } label: {
                    Text(title(item))
                        .font(MLFont.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isSelected ? Color.mlOnAccent : Color.mlTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.mlAccent)
                                    .matchedGeometryEffect(id: "seg", in: namespace)
                            }
                        }
                        .mlHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Color.mlSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.mlHairline, lineWidth: Layout.hairline))
    }
}

// MARK: - Previews

#Preview("SegmentedControl") {
    struct Demo: View {
        @State private var selection = "Overview"
        let items = ["Overview", "Corners", "Moments", "Weather"]
        var body: some View {
            MLSegmentedControl(items: items, title: { $0 }, selection: $selection)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mlBackground)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
