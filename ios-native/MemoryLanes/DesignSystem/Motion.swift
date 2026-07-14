import SwiftUI

// MARK: - Motion
//
// Motion communicates, it never decorates. Interactive elements use a single
// spring so the whole app feels like one physical system. Motion is limited to
// transforms and opacity so it stays smooth while maps and lists are moving.

enum Motion {
    /// Canonical interactive spring: responsive, physical, and quickly settled.
    static let spring = Animation.interpolatingSpring(
        mass: 0.8,
        stiffness: 300,
        damping: 30,
        initialVelocity: 0
    )
    /// Tighter spring for chips, symbols, and compact controls.
    static let springSnappy = Animation.interpolatingSpring(
        mass: 0.7,
        stiffness: 360,
        damping: 32,
        initialVelocity: 0
    )
    /// Softer spring for sheets and content arriving from off-screen.
    static let springGentle = Animation.interpolatingSpring(
        mass: 0.9,
        stiffness: 240,
        damping: 28,
        initialVelocity: 0
    )
    /// Opacity changes still use spring timing to keep motion language consistent.
    static let fade = springGentle
    /// A restrained spring pulse for skeleton placeholders.
    static let shimmer = Animation.interpolatingSpring(
        mass: 1,
        stiffness: 80,
        damping: 16,
        initialVelocity: 0
    ).repeatForever(autoreverses: true)

    static func reveal(index: Int) -> Animation {
        springGentle.delay(Double(index) * 0.02)
    }
}

// MARK: - Press feedback
//
// A reusable "press-scale" that gives every tappable surface the same
// physics-based response. Attach with `.mlPressable { … }`.

struct MLPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}

// MARK: - Spatial continuity

private struct MLStaggeredReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    let index: Int
    let distance: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : distance)
            .onAppear {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(Motion.reveal(index: index)) {
                        isVisible = true
                    }
                }
            }
    }
}

private struct MLHoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.001))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    .opacity(isHovering ? 1 : 0)
            }
            .scaleEffect(isHovering && !reduceMotion ? 1.02 : 1)
            .onHover { hovering in
                withAnimation(Motion.spring) {
                    isHovering = hovering
                }
            }
    }
}

extension View {
    /// Reveals sibling content from its source direction with a 20ms waterfall.
    func mlStaggeredReveal(index: Int, distance: CGFloat = 12) -> some View {
        modifier(MLStaggeredReveal(index: index, distance: distance))
    }

    /// Pointer-aware lift for interactive cards; inert on touch-only iPhones.
    func mlHoverLift(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(MLHoverLift(cornerRadius: cornerRadius))
    }
}
