import SwiftUI

// MARK: - Hex bootstrapping
//
// The design system is defined once, here, in terms of raw hex primitives and
// then exposed only as *semantic* tokens. Screens and components never reach for
// a raw hex value — they ask for `Color.mlBackground`, `Color.mlAccent`, etc.
// This is the single source of truth for colour in the app.

extension Color {
    /// Create a colour from a 6- or 8-digit hex string (`#RRGGBB` / `#RRGGBBAA`).
    /// Kept `private`-ish by convention: only the palette below should call it.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

private extension UIColor {
    /// Build a dynamic colour that resolves differently in light vs dark.
    /// This is the correct native mechanism for full dark-mode support without
    /// an asset catalog — the value is recomputed whenever the trait changes.
    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark)
                : UIColor(rgb: light)
        }
    }

    convenience init(rgb: UInt32) {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Palette (Tier 1: raw primitives — internal only)

private enum Palette {
    // True-dark surfaces (per brief: not navy, not grey).
    static let bg: UInt32          = 0x0A0A0A   // true dark background
    static let surface: UInt32     = 0x141414   // one step lighter — cards, sheets
    static let surfaceHigh: UInt32  = 0x1C1C1C   // elevated — modals, popovers
    static let hairline: UInt32    = 0x2A2A2A   // 1px separators on dark

    // Light-mode neutrals (kept restrained; app is dark-first).
    static let bgLight: UInt32      = 0xF6F6F7
    static let surfaceLight: UInt32  = 0xFFFFFF
    static let surfaceHiLight: UInt32 = 0xFFFFFF
    static let hairlineLight: UInt32  = 0xE3E3E6

    // Brand accent — one bold colour, owned and used sparingly.
    static let accent: UInt32       = 0x2EE6C0   // cyan/mint — the single accent
    static let accentPress: UInt32  = 0x12B89A

    // Semantic colours (never decorative).
    static let success: UInt32      = 0x30D158
    static let warning: UInt32      = 0xFFD60A
    static let danger: UInt32       = 0xFF453A
    static let info: UInt32         = 0x0A84FF
}

// MARK: - Semantic tokens (Tier 2: what the app actually uses)

extension Color {
    /// App background — true dark `#0A0A0A`.
    static let mlBackground = Color(uiColor: .dynamic(light: Palette.bgLight, dark: Palette.bg))
    /// Card / sheet surface — one step above the background.
    static let mlSurface = Color(uiColor: .dynamic(light: Palette.surfaceLight, dark: Palette.surface))
    /// Elevated surface — modals, popovers, the top-most layer.
    static let mlSurfaceElevated = Color(uiColor: .dynamic(light: Palette.surfaceHiLight, dark: Palette.surfaceHigh))
    /// Hairline separators and card borders.
    static let mlHairline = Color(uiColor: .dynamic(light: Palette.hairlineLight, dark: Palette.hairline))

    /// The one accent. Own it; use it sparingly.
    static let mlAccent = Color(hex: Palette.accent)
    static let mlAccentPressed = Color(hex: Palette.accentPress)

    // Text roles. Contrast on `#0A0A0A` meets WCAG AA.
    static let mlTextPrimary = Color(uiColor: .dynamic(light: 0x0A0A0A, dark: 0xF5F5F7))
    static let mlTextSecondary = Color(uiColor: .dynamic(light: 0x55606E, dark: 0x9A9AA0))
    static let mlTextTertiary = Color(uiColor: .dynamic(light: 0x8A8A8F, dark: 0x6A6A70))
    /// Text drawn *on* the accent fill (e.g. inside a primary button).
    static let mlOnAccent = Color(hex: 0x0A0A0A)

    // Semantic feedback.
    static let mlSuccess = Color(hex: Palette.success)
    static let mlWarning = Color(hex: Palette.warning)
    static let mlDanger  = Color(hex: Palette.danger)
    static let mlInfo    = Color(hex: Palette.info)
}

// MARK: - Gradients & effects

extension LinearGradient {
    /// Subtle accent gradient for hero elements — used sparingly.
    static let mlAccent = LinearGradient(
        colors: [Color.mlAccent, Color(hex: 0x0AB6E0)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Bottom-edge fade used to let a full-bleed map dissolve into the surface
    /// below it (Calimoto-style map-as-hero treatment).
    static func mlMapFade(_ surface: Color = .mlBackground) -> LinearGradient {
        LinearGradient(
            colors: [surface.opacity(0), surface],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
