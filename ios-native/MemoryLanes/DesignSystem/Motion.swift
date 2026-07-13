import SwiftUI

// MARK: - Motion
//
// Motion communicates, it never decorates. Interactive elements use a single
// spring so the whole app feels like one physical system. Page transitions
// slide or fade — they never bounce.

enum Motion {
    /// The canonical interactive spring (brief spec: response 0.4, damping 0.75).
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    /// Snappier spring for small controls (toggles, chips).
    static let springSnappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// Gentle fade for appearance / disappearance.
    static let fade = Animation.easeInOut(duration: 0.25)
    /// Shimmer sweep for skeleton loaders.
    static let shimmer = Animation.linear(duration: 1.1).repeatForever(autoreverses: false)
}

// MARK: - Press feedback
//
// A reusable "press-scale" that gives every tappable surface the same
// physics-based response. Attach with `.mlPressable { … }`.

struct MLPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}
