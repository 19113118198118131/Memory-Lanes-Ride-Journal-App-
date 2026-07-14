import SwiftUI

// MARK: - Toast
//
// A bottom-anchored, auto-dismissing notification with success / error / info
// variants. Presentation is driven through the environment so any screen fires
// one with `toast(.success("Ride saved"))` and never manages its own overlay.

struct Toast: Equatable, Identifiable {
    enum Kind {
        case success, error, info
        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .success: .mlSuccess
            case .error: .mlDanger
            case .info: .mlInfo
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let message: String

    static func success(_ m: String) -> Toast { .init(kind: .success, message: m) }
    static func error(_ m: String) -> Toast { .init(kind: .error, message: m) }
    static func info(_ m: String) -> Toast { .init(kind: .info, message: m) }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: toast.kind.symbol)
                .foregroundStyle(toast.kind.tint)
            Text(toast.message)
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.mlHairline, lineWidth: Layout.hairline))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }
}

// MARK: - Presentation modifier

private struct ToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var toast: Toast?
    var duration: TimeInterval = 2.5

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                ToastView(toast: toast)
                    .padding(.bottom, Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(duration))
                        withAnimation(reduceMotion ? nil : Motion.spring) { self.toast = nil }
                    }
            }
        }
        .animation(reduceMotion ? nil : Motion.spring, value: toast)
    }
}

extension View {
    /// Present auto-dismissing toasts bound to an optional `Toast`.
    func mlToast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

// MARK: - Previews

#Preview("Toasts") {
    struct Demo: View {
        @State private var toast: Toast?
        var body: some View {
            VStack(spacing: Spacing.md) {
                SecondaryButton(title: "Show success") { toast = .success("Ride saved to journal") }
                SecondaryButton(title: "Show error") { toast = .error("Couldn’t parse that GPX file") }
                SecondaryButton(title: "Show info") { toast = .info("Syncing with Strava…") }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mlBackground)
            .mlToast($toast)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
