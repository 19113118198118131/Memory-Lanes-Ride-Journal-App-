import SwiftUI

// MARK: - RideDetailView
//
// The ride's home: a full-bleed hero map, headline stats on a card that slides
// up over the map, an interactive elevation chart, and switchable sections for
// corners, moments, and weather. One-tap share renders a summary image.
//
// Assembled entirely from library components — the only bespoke work here is
// layout and the section switch.

struct RideDetailView: View {
    @State private var viewModel: RideDetailViewModel
    @State private var shareItem: ShareableImage?
    @State private var isRendering = false
    @Environment(\.dismiss) private var dismiss

    private let heroHeight: CGFloat = 340

    init(viewModel: RideDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    MLMapView(route: viewModel.ride.routePreview, fadeColor: .mlBackground)
                        .frame(height: heroHeight)

                    content
                        .background(
                            Color.mlBackground
                                .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
                        )
                        .offset(y: -28)
                        .padding(.bottom, -28)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            // Sibling of the ScrollView so it respects the top safe area while
            // the map stays full-bleed underneath it.
            floatingControls
        }
        .background(Color.mlBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.image])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Scrolling content

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            titleBlock

            SegmentedMetric(items: viewModel.headlineStats)
                .padding(.horizontal, Spacing.md)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline))

            MLSegmentedControl(
                items: RideDetailViewModel.Section.allCases,
                title: { $0.rawValue },
                selection: $viewModel.section
            )

            sectionContent
        }
        .padding(.top, Spacing.lg)
        .mlScreenPadding()
        .padding(.bottom, Spacing.xxl)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Text(viewModel.ride.source.rawValue).mlKicker()
                if let location = viewModel.ride.locationName {
                    Text("· \(location)").mlKicker()
                }
            }
            Text(viewModel.ride.title)
                .font(MLFont.title)
                .foregroundStyle(Color.mlTextPrimary)
            Text(viewModel.ride.dateFormatted)
                .mlCaption()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.section {
        case .overview: overviewSection
        case .corners: cornersSection
        case .moments: momentsSection
        case .weather: weatherSection
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let debrief = viewModel.detail?.debrief {
                debriefCard(debrief)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md),
                                GridItem(.flexible(), spacing: Spacing.md)],
                      spacing: Spacing.md) {
                StatCard(label: "Flow", value: viewModel.ride.flowScore.map(String.init) ?? "—",
                         systemImage: "waveform.path.ecg")
                StatCard(label: "Ascent", value: viewModel.ride.elevationFormatted, unit: "m",
                         systemImage: "mountain.2")
            }
            switch viewModel.state {
            case .loading:
                SkeletonBar(height: 180, radius: Radius.card).mlShimmer()
            case .loaded(let detail):
                ElevationChart(samples: detail.elevation)
            case .failed(let message):
                inlineError(message)
            }
        }
    }

    @ViewBuilder
    private var cornersSection: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: Spacing.md) {
                SkeletonBar(height: 150, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 150, radius: Radius.card).mlShimmer()
            }
        case .loaded(let detail):
            if detail.corners.isEmpty {
                EmptyState(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                           title: "No corners analysed",
                           message: "This ride didn’t have enough cornering data to build tickets.")
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(detail.corners) { CornerTicketCard(ticket: $0) }
                }
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    @ViewBuilder
    private var momentsSection: some View {
        switch viewModel.state {
        case .loading:
            SkeletonBar(height: 72, radius: Radius.card).mlShimmer()
        case .loaded(let detail):
            if detail.moments.isEmpty {
                EmptyState(systemImage: "sparkles",
                           title: "No moments captured",
                           message: "Pin a moment during a ride to remember exactly where it happened.")
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(detail.moments) { MomentRow(moment: $0) }
                }
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    @ViewBuilder
    private var weatherSection: some View {
        switch viewModel.state {
        case .loading:
            SkeletonBar(height: 96, radius: Radius.card).mlShimmer()
        case .loaded(let detail):
            if let weather = detail.weather {
                WeatherStrip(weather: weather)
            } else {
                EmptyState(systemImage: "cloud.sun",
                           title: "No weather on record",
                           message: "We couldn’t find historical weather for this ride’s time and place.")
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    private func debriefCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Ride Coach", systemImage: "quote.bubble.fill")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlAccent)
            Text(text)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mlAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .stroke(Color.mlAccent.opacity(0.25), lineWidth: Layout.hairline))
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(MLFont.callout)
            .foregroundStyle(Color.mlTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
    }

    // MARK: Floating controls

    private var floatingControls: some View {
        HStack {
            circleButton(systemImage: "chevron.left", label: "Back") { dismiss() }
            Spacer()
            circleButton(systemImage: isRendering ? "hourglass" : "square.and.arrow.up",
                         label: "Share ride") {
                renderShareImage()
            }
            .disabled(isRendering)
        }
        .mlScreenPadding()
        .padding(.top, Spacing.xs)
    }

    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.mlTextPrimary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.mlHairline, lineWidth: Layout.hairline))
        }
        .accessibilityLabel(label)
    }

    private func renderShareImage() {
        isRendering = true
        // ImageRenderer is main-actor bound; run on the next runloop tick so the
        // "rendering" state paints first, then hand the bitmap to the share sheet.
        Task { @MainActor in
            defer { isRendering = false }
            if let image = ShareCardRenderer.image(for: viewModel.ride) {
                Haptics.success()
                shareItem = ShareableImage(image: image)
            } else {
                Haptics.error()
            }
        }
    }
}

// MARK: - Previews

#Preview("RideDetail — loaded") {
    NavigationStack {
        RideDetailView(viewModel: RideDetailViewModel(
            ride: SampleData.hero,
            rideService: PreviewRideService()
        ))
    }
    .preferredColorScheme(.dark)
}

#Preview("RideDetail — error") {
    NavigationStack {
        RideDetailView(viewModel: RideDetailViewModel(
            ride: SampleData.hero,
            rideService: PreviewRideService(failure: .notImplemented)
        ))
    }
    .preferredColorScheme(.dark)
}
