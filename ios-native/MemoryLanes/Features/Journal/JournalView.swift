import SwiftUI

// MARK: - JournalView
//
// Native moments timeline and gallery. Uses the same Moment model as Ride
// Detail, so Supabase wiring later only needs to provide real moment rows.

struct JournalView: View {
    @State private var mode: JournalMode = .timeline
    private let moments = SampleData.moments

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header

                MLSegmentedControl(items: JournalMode.allCases, title: { $0.title }, selection: $mode)

                switch mode {
                case .timeline:
                    timeline
                case .gallery:
                    gallery
                }
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Ride memories").mlKicker()
            Text("Moments worth keeping")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Pinned notes, stops, photos, and personal bests from your rides.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    private var timeline: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Moment \(index + 1)").mlKicker()
                        Spacer()
                        Text(SampleData.hero.relativeDate)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextTertiary)
                    }
                    MomentRow(moment: moment)
                }
            }
        }
    }

    private var gallery: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ZStack(alignment: .bottomLeading) {
                        RouteThumbnail(route: SampleData.ridgeRoute)
                            .frame(height: 148)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay {
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.68)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: moment.symbol)
                                .foregroundStyle(Color.mlAccent)
                            Text("Moment \(index + 1)")
                                .font(MLFont.headline)
                                .foregroundStyle(Color.white)
                        }
                        .padding(Spacing.sm)
                    }

                    Text(moment.note)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(2)
                }
                .padding(Spacing.xs)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                )
            }
        }
    }
}

private enum JournalMode: String, CaseIterable, Identifiable {
    case timeline, gallery
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

#Preview {
    NavigationStack { JournalView() }
        .preferredColorScheme(.dark)
}
