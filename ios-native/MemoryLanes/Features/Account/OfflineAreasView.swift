import MapKit
import SwiftUI

struct OfflineAreasView: View {
    @State private var viewModel: OfflineAreasViewModel
    @State private var pendingRemoval: InstalledOfflineRegion?

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
                attribution
                    .mlStaggeredReveal(index: 5)
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
                    systemImage: "arrow.down.map",
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

    private var attribution: some View {
        Text("Offline road data © OpenStreetMap contributors, available under ODbL. Memory Lanes route scoring remains separate from the road database.")
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OfflineAreaSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: OfflineAreasViewModel
    @State private var position = MapCameraPosition.region(Self.initialRegion)
    @State private var selectedBounds = OfflineRegionBounds(
        south: -36.95,
        west: 174.52,
        north: -36.35,
        east: 175.05
    )
    @State private var isDownloading = false

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -36.65, longitude: 174.785),
        span: MKCoordinateSpan(latitudeDelta: 0.60, longitudeDelta: 0.53)
    )

    private var matchedRegions: [OfflineRegionDescriptor] {
        viewModel.regions(intersecting: selectedBounds)
    }

    private var pendingRegions: [OfflineRegionDescriptor] {
        matchedRegions.filter { !viewModel.isCurrent($0) }
    }

    private var selectionIsTooLarge: Bool {
        selectedBounds.north - selectedBounds.south > 1.6
            || selectedBounds.east - selectedBounds.west > 1.6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                selectionMap
                selectionSummary
                matchedAreaList
                PrimaryButton(
                    title: pendingRegions.isEmpty ? "Area Already Ready" : downloadTitle,
                    systemImage: "arrow.down.circle.fill",
                    isLoading: isDownloading
                ) {
                    Task { await downloadSelection() }
                }
                .disabled(selectionIsTooLarge || pendingRegions.isEmpty || isDownloading)
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Choose Area")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectionMap: some View {
        Map(position: $position, interactionModes: .all) {
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(selectionIsTooLarge ? Color.mlWarning : Color.mlAccent, lineWidth: Layout.hairline * 2)
                .padding(Spacing.xl)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Text("Move and zoom the map")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextPrimary)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: Layout.minTouchTarget)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(Spacing.sm)
        }
        .overlay {
            Image(systemName: "plus")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlTextPrimary)
                .allowsHitTesting(false)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            selectedBounds = OfflineRegionBounds(region: context.region)
        }
        .accessibilityLabel("Map for choosing offline road coverage")
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(selectionIsTooLarge ? "Zoom in to continue" : "Road packs in view")
                .font(MLFont.title2)
                .foregroundStyle(Color.mlTextPrimary)
            Text(selectionDescription)
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var matchedAreaList: some View {
        if matchedRegions.isEmpty {
            EmptyState(
                systemImage: "map",
                title: "No road pack here yet",
                message: "Move toward a supported area or refresh the catalog from Offline Areas."
            )
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
        if selectionIsTooLarge {
            return "Smaller selections keep downloads practical and routing fast on your phone."
        }
        if matchedRegions.isEmpty {
            return "Available road packs will appear as the catalog expands."
        }
        let bytes = pendingRegions.reduce(Int64(0)) { $0 + $1.byteCount }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return pendingRegions.isEmpty
            ? "Every road pack intersecting this selection is installed."
            : "\(pendingRegions.count) download\(pendingRegions.count == 1 ? "" : "s") · \(size)"
    }

    private var downloadTitle: String {
        pendingRegions.count == 1 ? "Download Area" : "Download \(pendingRegions.count) Areas"
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
    init(region: MKCoordinateRegion) {
        let latitudeHalf = region.span.latitudeDelta / 2
        let longitudeHalf = region.span.longitudeDelta / 2
        self.init(
            south: max(region.center.latitude - latitudeHalf, -90),
            west: max(region.center.longitude - longitudeHalf, -180),
            north: min(region.center.latitude + latitudeHalf, 90),
            east: min(region.center.longitude + longitudeHalf, 180)
        )
    }
}

#Preview {
    NavigationStack {
        OfflineAreasView()
    }
    .preferredColorScheme(.dark)
}
