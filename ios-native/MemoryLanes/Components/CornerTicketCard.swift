import SwiftUI

// MARK: - CornerTicketCard
//
// The "ticket" for one analysed corner: a geometry glyph, the IN › APEX › OUT
// speed progression, a verdict chip, a coaching tip, and repeat-corner
// recognition. Reads at a glance; rewards technique, never speed.

struct CornerTicketCard: View {
    let ticket: CornerTicket

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            speedProgression
            Text(ticket.tip)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let repeatNote = ticket.repeatNote {
                Label(repeatNote, systemImage: "trophy.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlAccent)
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: ticket.shape.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.mlAccent)
                .frame(width: 40, height: 40)
                .background(Color.mlAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Corner \(ticket.index)")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(ticket.shape.rawValue)
                    .mlCaption()
            }
            Spacer()
            VerdictChip(verdict: ticket.verdict)
        }
    }

    private var speedProgression: some View {
        HStack(spacing: Spacing.xs) {
            speedStop("IN", ticket.entrySpeed)
            connector
            speedStop("APEX", ticket.apexSpeed, emphasised: true)
            connector
            speedStop("OUT", ticket.exitSpeed)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func speedStop(_ label: String, _ value: Int, emphasised: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(MLFont.displaySmall)
                .foregroundStyle(emphasised ? Color.mlAccent : Color.mlTextPrimary)
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity)
    }

    private var connector: some View {
        Image(systemName: "chevron.compact.right")
            .font(.body)
            .foregroundStyle(Color.mlTextTertiary)
    }

    private var accessibilitySummary: String {
        "Corner \(ticket.index), \(ticket.shape.rawValue). In \(ticket.entrySpeed), apex \(ticket.apexSpeed), out \(ticket.exitSpeed) kilometres per hour. \(ticket.verdict.rawValue). \(ticket.tip)"
    }
}

// MARK: - VerdictChip

struct VerdictChip: View {
    let verdict: CornerTicket.Verdict

    private var tint: Color {
        switch verdict.tint {
        case .good: .mlSuccess
        case .warn: .mlWarning
        case .info: .mlInfo
        }
    }

    var body: some View {
        Text(verdict.rawValue)
            .font(MLFont.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Previews

#Preview("CornerTicketCard") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            ForEach(SampleData.corners) { CornerTicketCard(ticket: $0) }
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
