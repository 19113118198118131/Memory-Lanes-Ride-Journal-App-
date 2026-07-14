import SwiftUI

// MARK: - PrimaryButton
//
// Full-width accent fill, pill shape, haptic on tap, built-in loading state.
// While loading it disables itself and swaps the label for a progress view so a
// screen never has to manage a separate spinner.

struct PrimaryButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.mlOnAccent)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
            }
            .font(MLFont.headline)
            .foregroundStyle(Color.mlOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 52)
            .background(Color.mlAccent, in: Capsule())
            .opacity(isLoading ? 0.85 : 1)
        }
        .buttonStyle(MLPressableButtonStyle())
        .disabled(isLoading)
        .animation(reduceMotion ? nil : Motion.spring, value: isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - SecondaryButton
//
// Bordered, no fill. Same footprint as the primary so they line up in a stack.

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(MLFont.headline)
            .foregroundStyle(Color.mlTextPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 52)
            .background(
                Capsule().stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - DestructiveButton
//
// Red, and never fires directly — it presents a confirmation sheet first, so a
// destructive action always takes two intentional taps.

struct DestructiveButton: View {
    let title: String
    var confirmationTitle: String = "Are you sure?"
    var confirmationMessage: String? = nil
    var confirmActionTitle: String = "Delete"
    let action: () -> Void

    @State private var confirming = false

    var body: some View {
        Button(role: .destructive) {
            Haptics.warning()
            confirming = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "trash")
                Text(title)
            }
            .font(MLFont.headline)
            .foregroundStyle(Color.mlDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 52)
            .background(
                Capsule().stroke(Color.mlDanger.opacity(0.4), lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle())
        .confirmationDialog(
            confirmationTitle,
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(confirmActionTitle, role: .destructive) {
                Haptics.error()
                action()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let confirmationMessage { Text(confirmationMessage) }
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Previews

#Preview("Buttons — Dark") {
    VStack(spacing: Spacing.md) {
        PrimaryButton(title: "Start Ride", systemImage: "play.fill") {}
        PrimaryButton(title: "Uploading…", isLoading: true) {}
        SecondaryButton(title: "Import from Strava", systemImage: "square.and.arrow.down") {}
        DestructiveButton(
            title: "Delete Ride",
            confirmationMessage: "This permanently removes the ride and its GPX."
        ) {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}

#Preview("Buttons — Light") {
    VStack(spacing: Spacing.md) {
        PrimaryButton(title: "Start Ride", systemImage: "play.fill") {}
        SecondaryButton(title: "Import from Strava") {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.light)
}
