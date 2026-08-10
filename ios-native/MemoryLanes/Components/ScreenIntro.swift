import SwiftUI

/// Product-level hierarchy for the four primary tabs. Keeping this shared
/// preserves the same rhythm as features grow and copy changes.
struct ScreenIntro: View {
    let kicker: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(kicker)
                .mlKicker()
                .mlStaggeredReveal(index: 0, distance: Spacing.xs)

            Text(title)
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .mlStaggeredReveal(index: 1, distance: Spacing.sm)

            if let message {
                Text(message)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xxs)
                    .mlStaggeredReveal(index: 2, distance: Spacing.sm)
            }
        }
    }
}

#Preview("Screen intro") {
    ScreenIntro(
        kicker: "Routes & community",
        title: "The next ride starts here",
        message: "Meet your group, discover a community ride, or shape a route of your own."
    )
    .padding()
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
