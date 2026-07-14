import SwiftUI

// MARK: - Typography
//
// SF Pro is the system font, so we never bundle a font file — we ask for the
// system face at a semantic role. Every role is anchored to a Dynamic Type
// `TextStyle` via `relativeTo:`, so text scales with the user's accessibility
// setting instead of being frozen at a fixed point size.
//
// Roles (never mix more than three sizes on one screen):
//   • display  — hero numbers, ride stats, key metrics   (SF Pro Display, Heavy/Bold)
//   • title    — screen titles, card headers              (SF Pro Display, Semibold)
//   • body     — descriptions, labels                     (SF Pro Text, Regular)
//   • caption  — metadata, timestamps                     (SF Pro Text, Regular, secondary)
//   • mono     — GPS coordinates, technical values        (SF Mono)

enum MLFont {
    /// Giant hero metric — the single proud number on a screen.
    static let displayXL = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    /// Standard hero stat value inside a StatCard.
    static let display = Font.system(.title, design: .rounded).weight(.bold)
    /// Smaller hero value (e.g. a stat in a dense row).
    static let displaySmall = Font.system(.title2, design: .rounded).weight(.bold)

    /// Screen title.
    static let title = Font.system(.title, design: .default).weight(.bold)
    /// Card / section header.
    static let title2 = Font.system(.title3, design: .default).weight(.semibold)
    /// Prominent inline label / headline row.
    static let headline = Font.system(.headline).weight(.semibold)

    /// Default reading text.
    static let body = Font.system(.body)
    /// Emphasised body.
    static let bodyEmphasised = Font.system(.body).weight(.semibold)
    /// Labels, buttons.
    static let callout = Font.system(.callout).weight(.medium)

    /// Metadata, timestamps, secondary captions.
    static let caption = Font.system(.caption)
    /// Small all-caps kicker / eyebrow label.
    static let kicker = Font.system(.caption2).weight(.semibold)

    /// Technical values — GPS coordinates, raw sensor numbers.
    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
}

// MARK: - Text style helpers
//
// These wrap a font + colour + tracking into one modifier so a screen never
// re-specifies both. Use `.mlKicker()` etc. rather than styling ad-hoc.

extension View {
    /// Eyebrow label above a title — uppercase, tracked, tertiary colour.
    func mlKicker() -> some View {
        self.font(MLFont.kicker)
            .tracking(0)
            .textCase(.uppercase)
            .foregroundStyle(Color.mlTextTertiary)
    }

    /// Secondary caption styling (timestamps, metadata).
    func mlCaption() -> some View {
        self.font(MLFont.caption)
            .foregroundStyle(Color.mlTextSecondary)
    }
}
