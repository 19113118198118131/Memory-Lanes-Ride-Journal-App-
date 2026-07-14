import SwiftUI

// MARK: - Shimmer
//
// A moving highlight sweep. Applied to placeholder shapes while content loads,
// so loading states echo the shape of the real content instead of showing a
// spinner over an empty screen.

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var intensity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(reduceMotion ? 0.35 : 0.2 + (intensity * 0.8))
                .allowsHitTesting(false)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.shimmer) { intensity = 1 }
            }
            .clipped()
    }
}

extension View {
    /// Add an animated shimmer sweep (for skeleton placeholders).
    func mlShimmer() -> some View { modifier(Shimmer()) }
}

/// A single rounded placeholder bar.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = Radius.chip

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.mlSurfaceElevated)
            .frame(width: width, height: height)
    }
}

// MARK: - RideCardSkeleton
//
// The loading placeholder for the ride list — matches RideCard's silhouette so
// content swaps in without the layout jumping.

struct RideCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.mlSurfaceElevated)
                .frame(height: 148)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonBar(width: 180, height: 16)
                SkeletonBar(width: 120, height: 10)
                HStack(spacing: Spacing.lg) {
                    SkeletonBar(width: 48, height: 20)
                    SkeletonBar(width: 48, height: 20)
                    SkeletonBar(width: 48, height: 20)
                }
                .padding(.top, Spacing.xxs)
            }
            .padding(Spacing.md)
        }
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .mlShimmer()
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Skeletons") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            RideCardSkeleton()
            RideCardSkeleton()
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
