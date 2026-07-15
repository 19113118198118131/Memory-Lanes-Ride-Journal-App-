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
    var compact = false
    @Namespace private var namespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if compact && dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    segments(equalWidth: false)
                }
                .scrollIndicators(.hidden)
            } else {
                segments(equalWidth: true)
            }
        }
        .padding(Spacing.xxs)
        .background(Color.mlSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.mlHairline, lineWidth: Layout.hairline))
    }

    private func segments(equalWidth: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : Motion.spring) { selection = item }
                } label: {
                    Text(title(item))
                        .font(compact ? MLFont.caption.weight(.semibold) : MLFont.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(compact ? 0.88 : 0.7)
                        .foregroundStyle(isSelected ? Color.mlOnAccent : Color.mlTextSecondary)
                        .frame(maxWidth: equalWidth ? .infinity : nil)
                        .frame(minWidth: equalWidth ? nil : 92)
                        .frame(height: compact ? Layout.minTouchTarget : nil)
                        .padding(.vertical, compact ? 0 : Spacing.xs)
                        .padding(.horizontal, compact ? Spacing.xxs / 2 : 0)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.mlAccent)
                                    .matchedGeometryEffect(id: "seg", in: namespace)
                            }
                        }
                        .modifier(SegmentedHitTarget(enabled: !compact))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

private struct SegmentedHitTarget: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.mlHitTarget()
        } else {
            content.contentShape(Rectangle())
        }
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
