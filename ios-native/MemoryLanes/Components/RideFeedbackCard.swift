import SwiftUI

struct RideFeedbackCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let feedback: RideFeedback
    let isSaving: Bool
    let status: String?
    let onChange: (RideFeedback) -> Void

    private let reasons: [(key: String, title: String, positive: Bool)] = [
        ("likedCorners", "Great corners", true),
        ("likedScenery", "Great scenery", true),
        ("goodGroup", "Good group ride", true),
        ("tooUrban", "Too urban", false),
        ("tooMotorway", "Too much motorway", false),
        ("tooLong", "Too long", false),
        ("tooShort", "Too short", false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("YOUR RIDE").mlKicker()
                    Text("How did this feel?")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                if isSaving {
                    ProgressView().tint(.mlAccent)
                }
            }

            feedbackGroup(title: "Mood") {
                LazyVGrid(columns: feedbackColumns, alignment: .leading, spacing: Spacing.xs) {
                    ForEach(RideFeedback.Mood.allCases) { mood in
                        FeedbackChip(title: mood.title, isSelected: feedback.mood == mood) {
                            var updated = feedback
                            updated.mood = updated.mood == mood ? nil : mood
                            onChange(updated)
                        }
                    }
                }
            }

            feedbackGroup(title: "Enjoyment") {
                HStack(spacing: Spacing.xs) {
                    ForEach(1...5, id: \.self) { rating in
                        EnjoymentButton(rating: rating, isSelected: feedback.enjoyment == rating) {
                            var updated = feedback
                            updated.enjoyment = updated.enjoyment == rating ? nil : rating
                            onChange(updated)
                        }
                    }
                }
            }

            feedbackGroup(title: "Ride again?") {
                HStack(spacing: Spacing.xs) {
                    ForEach(RideFeedback.RepeatChoice.allCases) { choice in
                        FeedbackChip(title: choice.title, isSelected: feedback.wouldRepeat == choice) {
                            var updated = feedback
                            updated.wouldRepeat = updated.wouldRepeat == choice ? nil : choice
                            onChange(updated)
                        }
                    }
                }
            }

            feedbackGroup(title: "What shaped it?") {
                LazyVGrid(columns: feedbackColumns, alignment: .leading, spacing: Spacing.xs) {
                    ForEach(reasons, id: \.key) { reason in
                        FeedbackChip(title: reason.title, isSelected: feedback.reasons[reason.key] == true) {
                            var updated = feedback
                            updated.reasons[reason.key] = !(updated.reasons[reason.key] ?? false)
                            onChange(updated)
                        }
                    }
                }
            }

            if let status {
                Label(status, systemImage: status == "Saved. This shapes your route matches." ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(status.hasPrefix("Saved") ? Color.mlSuccess : Color.mlDanger)
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Color.mlHairline, lineWidth: Layout.hairline))
    }

    private func feedbackGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).mlKicker()
            content()
        }
    }

    private var feedbackColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Spacing.xs), GridItem(.flexible())]
    }
}

private struct EnjoymentButton: View {
    let rating: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(rating)")
                .font(MLFont.mono)
                .foregroundStyle(isSelected ? Color.mlOnAccent : Color.mlTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.minTouchTarget)
                .background(isSelected ? Color.mlAccent : Color.mlSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel("Enjoyment \(rating) out of 5")
    }
}

private struct FeedbackChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MLFont.callout)
                .foregroundStyle(isSelected ? Color.mlOnAccent : Color.mlTextSecondary)
                .padding(.horizontal, Spacing.sm)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Layout.minTouchTarget)
                .background(isSelected ? Color.mlAccent : Color.mlSurfaceElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(MLPressableButtonStyle())
    }
}
