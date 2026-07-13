import SwiftUI

// MARK: - BottomSheet
//
// A thin wrapper over the native `.presentationDetents` sheet so ride-detail
// stats slide up over the hero map with a real drag handle, native detents, and
// backdrop dismiss — rather than a hand-rolled overlay. Consistent chrome
// (drag handle, corner radius, surface colour) is applied here once.

struct BottomSheetChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.mlTextTertiary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)
                .accessibilityHidden(true)

            content
        }
        .frame(maxWidth: .infinity)
        .background(Color.mlSurface)
    }
}

extension View {
    /// Present a bottom sheet with app-standard detents, drag handle, and chrome.
    func mlBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            BottomSheetChrome { content() }
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden) // we draw our own handle
                .presentationBackground(Color.mlSurface)
                .presentationCornerRadius(28)
        }
    }
}

// MARK: - Previews

#Preview("BottomSheet") {
    struct Demo: View {
        @State private var show = true
        var body: some View {
            ZStack {
                Color.mlBackground.ignoresSafeArea()
                MLMapView(route: SampleData.ridgeRoute).ignoresSafeArea()
            }
            .mlBottomSheet(isPresented: $show) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(SampleData.hero.title).font(MLFont.title)
                            .foregroundStyle(Color.mlTextPrimary)
                        SegmentedMetric(items: [
                            .init(value: "84.3", unit: "km", label: "Distance"),
                            .init(value: "2h 12m", unit: "", label: "Time"),
                            .init(value: "1,240", unit: "m", label: "Ascent")
                        ])
                    }
                    .padding()
                }
            }
        }
    }
    return Demo().preferredColorScheme(.dark)
}
