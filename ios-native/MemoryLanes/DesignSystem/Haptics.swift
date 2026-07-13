import UIKit

// MARK: - Haptics
//
// A thin, centralised wrapper so haptic intent is expressed semantically at the
// call site (`Haptics.selection()`, `Haptics.success()`) rather than every view
// juggling raw `UIFeedbackGenerator` instances. Generators are created on demand
// and are cheap; `prepare()` is called to reduce latency on the first fire.

@MainActor
enum Haptics {
    /// Light tap — selection, toggles, card taps.
    static func selection() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    /// Medium tap — committing an action (start ride, save).
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }

    /// Success notification — completion of an import, save, or upload.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error notification — destructive confirm, failed operation.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
