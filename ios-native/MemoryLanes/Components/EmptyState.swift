import SwiftUI

// MARK: - EmptyState
//
// Every empty list gets one of these — never a blank screen. Icon, title, body,
// and an optional CTA. The copy should inspire the next ride, not apologise for
// the absence of data.

struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.mlAccent)
                .padding(Spacing.lg)
                .background(Color.mlAccent.opacity(0.10), in: Circle())

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .frame(maxWidth: 260)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Previews

#Preview("EmptyState — with CTA") {
    EmptyState(
        systemImage: "map",
        title: "No rides yet",
        message: "Upload a GPX track or start a live ride, and your first journal entry will appear here.",
        actionTitle: "Start Your First Ride"
    ) {}
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}

#Preview("EmptyState — no CTA") {
    EmptyState(
        systemImage: "sparkles",
        title: "No moments captured",
        message: "Pin a moment during a ride to remember exactly where it happened."
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
