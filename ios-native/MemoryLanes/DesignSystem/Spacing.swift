import SwiftUI

// MARK: - Spacing
//
// Base unit is 4pt. Every padding, gap, and inset in the app is a member of
// this scale — there are no magic numbers in view code. If a value you need
// isn't here, it doesn't belong in the design; adjust the design.

enum Spacing {
    /// 4pt — hairline gaps, icon-to-label.
    static let xxs: CGFloat = 4
    /// 8pt — tight internal padding, chip padding.
    static let xs: CGFloat = 8
    /// 12pt — compact card padding, stack gaps.
    static let sm: CGFloat = 12
    /// 16pt — default card padding, standard gap.
    static let md: CGFloat = 16
    /// 20pt — the consistent horizontal screen margin.
    static let screenH: CGFloat = 20
    /// 24pt — section gaps.
    static let lg: CGFloat = 24
    /// 32pt — large section separation.
    static let xl: CGFloat = 32
    /// 48pt — hero / empty-state breathing room.
    static let xxl: CGFloat = 48
}

// MARK: - Corner radius
//
// One radius per role. Never mix radius values on the same surface.

enum Radius {
    /// Cards, sheets.
    static let card: CGFloat = 16
    /// Standard buttons, inputs.
    static let button: CGFloat = 12
    /// Chips, tags, small controls.
    static let chip: CGFloat = 8
    /// Pill CTAs and filters.
    static let pill: CGFloat = 999
}

// MARK: - Layout constants

enum Layout {
    /// Minimum touch target (HIG). Use `.contentShape` to guarantee it.
    static let minTouchTarget: CGFloat = 44
    /// Hairline width.
    static let hairline: CGFloat = 1
    /// Maximum width of controls docked beside content on a compact-height screen.
    static let compactPanelMaxWidth: CGFloat = 360
}

extension View {
    /// Apply the standard 20pt horizontal screen margin.
    func mlScreenPadding() -> some View {
        self.padding(.horizontal, Spacing.screenH)
    }

    /// Guarantee an interactive element is at least 44×44pt and fully hittable.
    func mlHitTarget() -> some View {
        self.frame(minWidth: Layout.minTouchTarget, minHeight: Layout.minTouchTarget)
            .contentShape(Rectangle())
    }
}
