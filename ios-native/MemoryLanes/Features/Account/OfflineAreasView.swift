import MapKit
import SwiftUI

struct OfflineAreasView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: OfflineAreasViewModel
    @State private var pendingRemoval: InstalledOfflineRegion?
    @State private var showsRoutingDiagnostics = false

    init(viewModel: OfflineAreasViewModel = OfflineAreasViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                overview
                    .mlStaggeredReveal(index: 0)
                addAreaAction
                    .mlStaggeredReveal(index: 1)
                installedSection
                    .mlStaggeredReveal(index: 2)
                availableSection
                    .mlStaggeredReveal(index: 3)
                downloadSettings
                    .mlStaggeredReveal(index: 4)
                routingDiagnostics
                    .mlStaggeredReveal(index: 5)
                attribution
                    .mlStaggeredReveal(index: 6)
            }
            .padding(.vertical, Spacing.lg)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Offline Areas")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load(forceRefresh: true) }
        .task { await viewModel.load() }
        .mlToast($viewModel.toast)
        .confirmationDialog(
            "Remove offline area?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let pendingRemoval else { return }
                Task { await viewModel.remove(pendingRemoval) }
                self.pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Routes and rides remain in your library. Only the downloaded road data is removed.")
        }
    }

    private var overview: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle().fill(Color.mlAccent.opacity(0.14))
                Image(systemName: "map.fill")
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlAccent)
            }
            .frame(width: Layout.accountAvatarSize, height: Layout.accountAvatarSize)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Local road library").mlKicker()
                Text(viewModel.readinessText)
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("\(viewModel.storageText) on this iPhone")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addAreaAction: some View {
        NavigationLink {
            OfflineAreaSelectionView(viewModel: viewModel)
        } label: {
            Label("Choose Area on Map", systemImage: "plus")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlOnAccent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Spacing.xxl + Spacing.xs)
                .background(Color.mlAccent, in: Capsule())
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityHint("Opens a map for selecting offline road coverage")
    }

    @ViewBuilder
    private var installedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Downloaded")
            if viewModel.installed.isEmpty {
                EmptyState(
                    systemImage: "map.fill",
                    title: "No areas downloaded",
                    message: "Choose roads around home or somewhere you plan to ride."
                )
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(viewModel.installed) { region in
                        OfflineRegionCard(
                            descriptor: region.descriptor,
                            status: .installed(
                                updateAvailable: region.needsUpdate(
                                    comparedWith: viewModel.available.first { $0.id == region.id }
                                )
                            ),
                            installPhase: viewModel.installPhases[region.id],
                            onDownload: {
                                let available = viewModel.available.first { $0.id == region.id }
                                    ?? region.descriptor
                                Task { _ = await viewModel.install(available) }
                            },
                            onRemove: { pendingRemoval = region }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Suggested Areas", actionTitle: viewModel.catalogError == nil ? nil : "Retry") {
                Task { await viewModel.load(forceRefresh: true) }
            }

            if viewModel.isLoading && viewModel.available.isEmpty {
                VStack(spacing: Spacing.sm) {
                    SkeletonBar(height: 104, radius: Radius.card).mlShimmer()
                    SkeletonBar(height: 104, radius: Radius.card).mlShimmer()
                }
            } else if let catalogError = viewModel.catalogError, viewModel.available.isEmpty {
                EmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Catalog unavailable",
                    message: catalogError
                )
            } else if viewModel.available.isEmpty {
                EmptyState(
                    systemImage: "map",
                    title: "No road packs published",
                    message: "Pull to refresh or check again after offline coverage expands."
                )
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(viewModel.available.filter { !viewModel.isCurrent($0) }) { region in
                        OfflineRegionCard(
                            descriptor: region,
                            status: viewModel.installedRegion(for: region) == nil ? .available : .update,
                            installPhase: viewModel.installPhases[region.id],
                            onDownload: { Task { _ = await viewModel.install(region) } },
                            onRemove: nil
                        )
                    }
                }
            }
        }
    }

    private var downloadSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Downloads").mlKicker()
            Toggle(isOn: $viewModel.wifiOnly) {
                Label {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Wi-Fi only")
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text("Avoid using mobile data for road packs")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                } icon: {
                    Image(systemName: "wifi")
                        .foregroundStyle(Color.mlAccent)
                }
            }
            .tint(.mlAccent)
            .padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private var routingDiagnostics: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : Motion.spring) {
                    showsRoutingDiagnostics.toggle()
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Spacing.xl)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Routing diagnostics")
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text(viewModel.routingDiagnosticsSummary)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .rotationEffect(.degrees(showsRoutingDiagnostics ? 180 : 0))
                }
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel(showsRoutingDiagnostics ? "Hide routing diagnostics" : "Show routing diagnostics")

            if showsRoutingDiagnostics {
                Divider().overlay(Color.mlHairline)
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: 0) {
                        diagnosticMetric(
                            value: "\(viewModel.routingDiagnostics.localRouteCount)",
                            label: "Local routes"
                        )
                        Divider().overlay(Color.mlHairline)
                        diagnosticMetric(
                            value: "\(viewModel.routingDiagnostics.fallbackCount)",
                            label: "MapKit fallbacks"
                        )
                    }
                    .frame(minHeight: Layout.minTouchTarget)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        diagnosticDetail(label: "Last pack", value: viewModel.lastRoutingPackText)
                        diagnosticDetail(label: "Last local issue", value: viewModel.lastFallbackText)
                        diagnosticDetail(label: "Last check", value: viewModel.lastRoutingDurationText)
                    }

                    Button("Reset diagnostics", systemImage: "arrow.counterclockwise") {
                        Task { await viewModel.resetRoutingDiagnostics() }
                    }
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .frame(minHeight: Layout.minTouchTarget)
                    .buttonStyle(MLPressableButtonStyle())

                    Text("Stored only on this iPhone. Locations and route geometry are never included.")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        }
    }

    private func diagnosticMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(MLFont.title2)
                .foregroundStyle(Color.mlTextPrimary)
                .monospacedDigit()
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
    }

    private func diagnosticDetail(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .font(MLFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.mlTextSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var attribution: some View {
        Text("Offline road data © OpenStreetMap contributors, available under ODbL. Memory Lanes route scoring remains separate from the road database.")
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OfflineAreaSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: OfflineAreasViewModel
    @State private var position = MapCameraPosition.region(Self.initialRegion)
    @State private var areaSize = OfflineAreaSize.nearby
    @State private var selectedBounds = OfflineRegionBounds.centered(
        at: Self.initialCenter,
        sideKilometers: OfflineAreaSize.nearby.sideKilometers
    )
    @State private var isDownloading = false

    private static let initialCenter = Coordinate(latitude: -36.65, longitude: 174.785)
    private static let initialRegion = MKCoordinateRegion(
        center: initialCenter.clCoordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.60, longitudeDelta: 0.53)
    )

    private var matchedRegions: [OfflineRegionDescriptor] {
        viewModel.regions(intersecting: selectedBounds)
    }

    private var pendingRegions: [OfflineRegionDescriptor] {
        matchedRegions.filter { !viewModel.isCurrent($0) }
    }

    private var coverageFraction: Double {
        viewModel.coverageFraction(for: selectedBounds)
    }

    private var installedCoverageFraction: Double {
        viewModel.installedCoverageFraction(for: selectedBounds)
    }

    private var coveragePercentage: Int {
        Int((coverageFraction * 100).rounded())
    }

    private var selectionTint: Color {
        if installedCoverageFraction >= 0.995 { return .mlSuccess }
        if coverageFraction >= 0.995 { return .mlAccent }
        if coverageFraction > 0 { return .mlWarning }
        return .mlTextTertiary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                areaSizeControl
                selectionMap
                selectionSummary
                matchedAreaList
                selectionAction
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Choose Area")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load(forceRefresh: true) }
    }

    private var areaSizeControl: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Area size").mlKicker()
                Spacer()
                Text(areaSize.detail)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }
            MLSegmentedControl(
                items: OfflineAreaSize.allCases,
                title: { $0.title },
                selection: $areaSize,
                compact: true
            )
        }
        .onChange(of: areaSize) { _, newValue in
            let bounds = OfflineRegionBounds.centered(
                at: selectedBounds.center,
                sideKilometers: newValue.sideKilometers
            )
            withAnimation(reduceMotion ? nil : Motion.spring) {
                selectedBounds = bounds
                position = .region(bounds.mapRegion(padding: 1.55))
            }
        }
    }

    private var selectionMap: some View {
        Map(position: $position, interactionModes: .all) {
            ForEach(viewModel.available) { region in
                MapPolygon(coordinates: region.bounds.mapCoordinates)
                    .foregroundStyle(
                        (viewModel.isCurrent(region) ? Color.mlSuccess : Color.mlAccent).opacity(0.10)
                    )
                    .stroke(
                        viewModel.isCurrent(region) ? Color.mlSuccess : Color.mlAccent,
                        lineWidth: Layout.hairline * 2
                    )
            }
            MapPolygon(coordinates: selectedBounds.mapCoordinates)
                .foregroundStyle(selectionTint.opacity(0.10))
                .stroke(selectionTint, lineWidth: Layout.hairline * 3)
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .top) {
            HStack(spacing: Spacing.xs) {
                Label("Drag to choose", systemImage: "hand.draw.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(minHeight: Layout.minTouchTarget)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button {
                    Haptics.selection()
                    position = .userLocation(followsHeading: false, fallback: .region(Self.initialRegion))
                } label: {
                    Image(systemName: "location.fill")
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(MLPressableButtonStyle())
                .accessibilityLabel("Choose area around my location")
            }
            .padding(Spacing.sm)
        }
        .overlay {
            Image(systemName: "scope")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlTextPrimary)
                .allowsHitTesting(false)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            selectedBounds = OfflineRegionBounds.centered(
                at: Coordinate(
                    latitude: context.region.center.latitude,
                    longitude: context.region.center.longitude
                ),
                sideKilometers: areaSize.sideKilometers
            )
        }
        .accessibilityLabel("Map for choosing offline road coverage")
    }

    private var selectionSummary: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Circle().fill(selectionTint.opacity(0.14))
                Image(systemName: coverageFraction > 0 ? "map.fill" : "map")
                    .font(MLFont.headline)
                    .foregroundStyle(selectionTint)
            }
            .frame(width: Spacing.xxl, height: Spacing.xxl)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(selectionTitle)
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(selectionDescription)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var matchedAreaList: some View {
        if matchedRegions.isEmpty {
            VStack(spacing: Spacing.sm) {
                EmptyState(
                    systemImage: viewModel.catalogError == nil ? "map" : "wifi.exclamationmark",
                    title: viewModel.catalogError == nil ? "Not available here yet" : "Catalog unavailable",
                    message: emptySelectionMessage
                )
                if let nearest = viewModel.nearestAvailableRegion(to: selectedBounds.center) {
                    SecondaryButton(
                        title: "Show \(nearest.name)",
                        systemImage: "location.viewfinder"
                    ) {
                        focus(on: nearest)
                    }
                }
            }
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(matchedRegions) { region in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: viewModel.isCurrent(region) ? "checkmark.circle.fill" : "map.fill")
                            .font(MLFont.headline)
                            .foregroundStyle(viewModel.isCurrent(region) ? Color.mlSuccess : Color.mlAccent)
                            .frame(width: Spacing.xl)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(region.name)
                                .font(MLFont.bodyEmphasised)
                                .foregroundStyle(Color.mlTextPrimary)
                            Text(viewModel.isCurrent(region) ? "Ready offline" : region.sizeText)
                                .font(MLFont.caption)
                                .foregroundStyle(Color.mlTextSecondary)
                        }
                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
    }

    private var selectionDescription: String {
        if matchedRegions.isEmpty {
            return viewModel.catalogError == nil
                ? "Move the map to published coverage. More regions can be added without updating the app."
                : "The road-pack catalog could not be refreshed."
        }
        let bytes = pendingRegions.reduce(Int64(0)) { $0 + $1.byteCount }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        if installedCoverageFraction >= 0.995 {
            return "This selection is ready for offline route planning and guidance."
        }
        if pendingRegions.isEmpty {
            return "Installed roads cover \(coveragePercentage)% of this selection."
        }
        let coverage = coverageFraction >= 0.995 ? "Full coverage" : "\(coveragePercentage)% coverage"
        return "\(coverage) · \(pendingRegions.count) pack\(pendingRegions.count == 1 ? "" : "s") · \(size)"
    }

    private var selectionTitle: String {
        if installedCoverageFraction >= 0.995 { return "Ready offline" }
        if coverageFraction >= 0.995 { return "Full coverage available" }
        if coverageFraction > 0 { return "Partial coverage available" }
        return "Choose a covered area"
    }

    private var downloadTitle: String {
        pendingRegions.count == 1 ? "Download Area" : "Download \(pendingRegions.count) Areas"
    }

    @ViewBuilder
    private var selectionAction: some View {
        if matchedRegions.isEmpty {
            SecondaryButton(
                title: viewModel.isLoading ? "Refreshing Catalog" : "Refresh Catalog",
                systemImage: "arrow.clockwise"
            ) {
                Task { await viewModel.load(forceRefresh: true) }
            }
            .disabled(viewModel.isLoading)
            .accessibilityHint("Checks for newly published offline road packs")
        } else {
            PrimaryButton(
                title: pendingRegions.isEmpty ? "Available Roads Ready" : downloadTitle,
                systemImage: pendingRegions.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                isLoading: isDownloading
            ) {
                Task { await downloadSelection() }
            }
            .disabled(pendingRegions.isEmpty || isDownloading)
        }
    }

    private var emptySelectionMessage: String {
        if let catalogError = viewModel.catalogError {
            return "Refresh to try again. \(catalogError)"
        }
        return "Published coverage is outlined on the map. Move there, or refresh to check for new areas."
    }

    private func focus(on region: OfflineRegionDescriptor) {
        Haptics.selection()
        let bounds = OfflineRegionBounds.centered(
            at: region.bounds.center,
            sideKilometers: min(areaSize.sideKilometers, 25)
        )
        if areaSize != .nearby { areaSize = .nearby }
        selectedBounds = bounds
        withAnimation(reduceMotion ? nil : Motion.spring) {
            position = .region(region.bounds.mapRegion(padding: 1.18))
        }
    }

    private func downloadSelection() async {
        guard !isDownloading else { return }
        isDownloading = true
        let success = await viewModel.install(pendingRegions)
        isDownloading = false
        if success { dismiss() }
    }
}

private struct OfflineRegionCard: View {
    enum Status {
        case available
        case update
        case installed(updateAvailable: Bool)
    }

    let descriptor: OfflineRegionDescriptor
    let status: Status
    let installPhase: OfflineRegionInstallPhase?
    let onDownload: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Color.mlAccent.opacity(0.12))
                Image(systemName: "map.fill")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlAccent)
            }
            .frame(width: Spacing.xxl, height: Spacing.xxl)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(descriptor.name)
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(installPhase?.title ?? descriptor.detail)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .lineLimit(2)
                Text("\(descriptor.sizeText) · v\(descriptor.version)")
                    .mlKicker()
                    .monospacedDigit()
            }

            Spacer(minLength: Spacing.xs)

            if installPhase != nil {
                ProgressView().tint(.mlAccent).mlHitTarget()
            } else {
                trailingAction
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch status {
        case .available:
            iconButton("arrow.down.circle.fill", label: "Download \(descriptor.name)", action: onDownload)
        case .update:
            iconButton("arrow.triangle.2.circlepath.circle.fill", label: "Update \(descriptor.name)", action: onDownload)
        case .installed(let updateAvailable):
            if updateAvailable {
                iconButton("arrow.triangle.2.circlepath.circle.fill", label: "Update \(descriptor.name)", action: onDownload)
            } else if let onRemove {
                iconButton("trash", label: "Remove \(descriptor.name)", tint: .mlTextTertiary, action: onRemove)
            }
        }
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        tint: Color = .mlAccent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(MLFont.headline)
                .foregroundStyle(tint)
                .mlHitTarget()
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel(label)
    }
}

private extension OfflineRegionBounds {
    var mapCoordinates: [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: north, longitude: west),
            CLLocationCoordinate2D(latitude: north, longitude: east),
            CLLocationCoordinate2D(latitude: south, longitude: east),
            CLLocationCoordinate2D(latitude: south, longitude: west)
        ]
    }

    func mapRegion(padding: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: (north - south) * padding,
                longitudeDelta: (east - west) * padding
            )
        )
    }
}

#Preview {
    NavigationStack {
        OfflineAreasView()
    }
    .preferredColorScheme(.dark)
}
