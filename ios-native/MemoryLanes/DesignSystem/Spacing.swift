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
    /// Native sheets and full-height drawers.
    static let sheet: CGFloat = 28
}

// MARK: - Layout constants

enum Layout {
    /// Minimum touch target (HIG). Use `.contentShape` to guarantee it.
    static let minTouchTarget: CGFloat = 44
    /// Hairline width.
    static let hairline: CGFloat = 1
    /// Maximum width of controls docked beside content on a compact-height screen.
    static let compactPanelMaxWidth: CGFloat = 360
    /// Speed-first live recorder instrument in landscape. Wide enough for an
    /// arrival time and remaining distance without truncating either value.
    static let liveCockpitMaxWidth: CGFloat = 360
    /// Stable maneuver symbol in the live navigation banner.
    static let navigationManeuverSize: CGFloat = 64
    /// Keeps downloaded-area map framing clear of its bottom readiness panel.
    static let offlineMapDetailBottomInset: CGFloat = 144
    /// Brand mark width on the signed-out welcome experience.
    static let welcomeBrandMarkMaxWidth: CGFloat = 280
    /// Decorative mark yields space to content at accessibility text sizes.
    static let welcomeBrandMarkAccessibilityWidth: CGFloat = 220
    /// Rider identity mark on the account screen.
    static let accountAvatarSize: CGFloat = 72
    /// Prominent symbol used when a screen has no content yet.
    static let emptyStateIconSize: CGFloat = 72
    /// Stable circular target in the route direction compass.
    static let routeCompassButtonSize: CGFloat = 56
    /// Keeps the final scroll item comfortably above the floating tab bar.
    static let floatingTabBarClearance: CGFloat = 96
    /// Raises transient feedback above the floating tab bar.
    static let floatingTabBarToastInset: CGFloat = 72
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

    /// Give scroll content a deliberate resting position above the tab shell.
    func mlTabBarContentClearance() -> some View {
        self.padding(.bottom, Layout.floatingTabBarClearance)
    }

    /// A subtle edge keeps maps and imagery crisp against true-dark surfaces.
    func mlMediaOutline(cornerRadius: CGFloat = Radius.card) -> some View {
        self.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.mlTextPrimary.opacity(0.10), lineWidth: Layout.hairline)
                .allowsHitTesting(false)
        }
    }
}
