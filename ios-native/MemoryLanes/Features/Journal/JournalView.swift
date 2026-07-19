import SwiftUI

// MARK: - JournalView
//
// Cross-ride moments timeline. This now reads the same `ride_logs.moments`
// payload as the web app, so the native Journal is no longer sample content.

struct JournalView: View {
    @State private var viewModel: JournalViewModel
    @State private var mode: JournalMode = .timeline
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let refreshTrigger: UUID
    let onSelectRide: (Ride) -> Void

    init(
        viewModel: JournalViewModel,
        refreshTrigger: UUID = UUID(),
        onSelectRide: @escaping (Ride) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.refreshTrigger = refreshTrigger
        self.onSelectRide = onSelectRide
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header
                MLSegmentedControl(items: JournalMode.allCases, title: { $0.title }, selection: $mode)
                content
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task(id: refreshTrigger) { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Ride memories").mlKicker()
            Text("Moments worth keeping")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Pinned notes and favourite stops from your saved rides.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LazyVStack(spacing: Spacing.md) {
                MomentSkeleton()
                MomentSkeleton()
                MomentSkeleton()
            }
        case .loaded(let entries):
            switch mode {
            case .timeline:
                timeline(entries)
            case .gallery:
                gallery(entries)
            }
        case .empty:
            EmptyState(
                systemImage: "mappin.and.ellipse",
                title: "No moments yet",
                message: "Pin a moment during ride replay or while recording, and it will appear here."
            )
            .padding(.top, Spacing.xl)
        case .failed(let message):
            EmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Couldn’t load moments",
                message: message,
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, Spacing.xl)
        }
    }

    private func timeline(_ entries: [JournalEntry]) -> some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(entries) { entry in
                JournalMomentCard(entry: entry, compact: false) {
                    onSelectRide(entry.ride)
                }
            }
        }
    }

    private func gallery(_ entries: [JournalEntry]) -> some View {
        LazyVGrid(columns: galleryColumns, spacing: Spacing.md) {
            ForEach(entries) { entry in
                JournalMomentCard(entry: entry, compact: true) {
                    onSelectRide(entry.ride)
                }
            }
        }
    }

    private var galleryColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }
}

private struct JournalMomentCard: View {
    let entry: JournalEntry
    var compact: Bool
    let onOpenRide: () -> Void

    var body: some View {
        Button(action: onOpenRide) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if compact {
                    compactArtwork
                }
                header
                Text(entry.displayNote)
                    .font(compact ? MLFont.caption : MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(compact ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                metadata
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel("\(entry.displayTitle). \(entry.displayNote). From \(entry.ride.title)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: entry.coordinate == nil ? "note.text" : "mappin.circle.fill")
                .font(MLFont.bodyEmphasised)
                .foregroundStyle(Color.mlAccent)
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(Color.mlAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.displayTitle)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(2)
                Text(entry.ride.title)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            Image(systemName: "chevron.right")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
        }
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                metadataLabels
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                metadataLabels
            }
        }
        .font(MLFont.caption)
        .foregroundStyle(Color.mlTextTertiary)
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(entry.relativeDate, systemImage: "calendar")
        if let speedKmh = entry.speedKmh {
            Label("\(Int(speedKmh.rounded())) km/h", systemImage: "speedometer")
                .monospacedDigit()
        }
        if let elevation = entry.elevationMeters {
            Label("\(Int(elevation.rounded())) m", systemImage: "mountain.2.fill")
                .monospacedDigit()
        }
    }

    private var compactArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            RouteThumbnail(route: entry.ride.routePreview.isEmpty ? SampleData.ridgeRoute : entry.ride.routePreview)
                .frame(height: 122)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }

            Text(entry.ride.source.rawValue)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(Spacing.sm)
        }
    }
}

private struct MomentSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.mlSurfaceElevated)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Capsule().fill(Color.mlSurfaceElevated).frame(width: 160, height: 14)
                    Capsule().fill(Color.mlSurfaceElevated).frame(width: 110, height: 10)
                }
            }
            Capsule().fill(Color.mlSurfaceElevated).frame(height: 12)
            Capsule().fill(Color.mlSurfaceElevated).frame(width: 220, height: 12)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .redacted(reason: .placeholder)
    }
}

private enum JournalMode: String, CaseIterable, Identifiable {
    case timeline, gallery
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

#Preview {
    NavigationStack {
        JournalView(viewModel: JournalViewModel(journalService: PreviewJournalService()))
    }
    .preferredColorScheme(.dark)
}
