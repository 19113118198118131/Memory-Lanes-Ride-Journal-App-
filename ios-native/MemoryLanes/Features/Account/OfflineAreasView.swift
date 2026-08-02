import SwiftUI

struct OfflineAreasView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: OfflineAreasViewModel
    @State private var pendingMapRemoval: OfflineMapArea?
    @State private var editingArea: OfflineMapArea?
    @State private var editedName = ""
    @State private var showsDownloadSettings = false
    @State private var showsRoutingDiagnostics = false

    init(viewModel: OfflineAreasViewModel = OfflineAreasViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                overview.mlStaggeredReveal(index: 0)
                addAreaAction.mlStaggeredReveal(index: 1)
                downloadedMaps.mlStaggeredReveal(index: 2)
                downloadSettings.mlStaggeredReveal(index: 3)
                attribution.mlStaggeredReveal(index: 4)
            }
            .padding(.vertical, Spacing.lg)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Offline Maps")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load(forceRefresh: true) }
        .task { await viewModel.load() }
        .task(id: viewModel.activeMapDownloadCount) {
            guard viewModel.activeMapDownloadCount > 0 else { return }
            while !Task.isCancelled, viewModel.activeMapDownloadCount > 0 {
                try? await Task.sleep(for: .seconds(1))
                await viewModel.refreshMapAreas()
            }
        }
        .mlToast($viewModel.toast)
        .confirmationDialog(
            "Remove offline map?",
            isPresented: Binding(
                get: { pendingMapRemoval != nil },
                set: { if !$0 { pendingMapRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Download", role: .destructive) {
                guard let area = pendingMapRemoval else { return }
                Task { await viewModel.removeMapArea(area) }
                pendingMapRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingMapRemoval = nil }
        } message: {
            Text("The map and any route data used only by this area are removed from this iPhone. Saved routes and recorded rides stay in your library.")
        }
        .alert(
            "Rename Offline Map",
            isPresented: Binding(
                get: { editingArea != nil },
                set: { if !$0 { editingArea = nil } }
            )
        ) {
            TextField("Area name", text: $editedName)
            Button("Save") {
                guard let area = editingArea else { return }
                Task { await viewModel.renameMapArea(area, to: editedName) }
                editingArea = nil
            }
            Button("Cancel", role: .cancel) { editingArea = nil }
        } message: {
            Text("Use a name you will recognize before a ride.")
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
                Text("On this iPhone").mlKicker()
                Text(viewModel.readinessText)
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("\(viewModel.storageText) stored")
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
            Label("Download New Area", systemImage: "arrow.down.to.line.compact")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlOnAccent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Spacing.xxl + Spacing.xs)
                .background(Color.mlAccent, in: Capsule())
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityHint("Opens a map where you can choose exactly what to store offline")
    }

    @ViewBuilder
    private var downloadedMaps: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Downloaded Areas")
            if viewModel.isLoading && viewModel.mapAreas.isEmpty {
                VStack(spacing: Spacing.sm) {
                    SkeletonBar(height: 132, radius: Radius.card).mlShimmer()
                    SkeletonBar(height: 132, radius: Radius.card).mlShimmer()
                }
            } else if viewModel.mapAreas.isEmpty {
                EmptyState(
                    systemImage: "map",
                    title: "No offline areas yet",
                    message: "Choose a ride area once. Memory Lanes will prepare its map, route planning and navigation for offline use where coverage is available."
                )
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(viewModel.mapAreas) { area in
                        OfflineMapAreaCard(
                            area: area,
                            capability: viewModel.capability(for: area),
                            needsSetup: viewModel.needsRoutingSetup(for: area),
                            isCompletingSetup: viewModel.isCompletingSetup(for: area),
                            onResume: { Task { await viewModel.resumeMapArea(area) } },
                            onCompleteSetup: { Task { await viewModel.completeOfflineSetup(for: area) } },
                            onRename: {
                                editedName = area.name
                                editingArea = area
                            },
                            onRemove: { pendingMapRemoval = area }
                        )
                    }
                }
            }
        }
    }

    private var downloadSettings: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : Motion.spring) {
                    showsDownloadSettings.toggle()
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "gearshape.fill")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Spacing.xl)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Download settings")
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text("Wi-Fi preference and private diagnostics")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .rotationEffect(.degrees(showsDownloadSettings ? 180 : 0))
                }
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(MLPressableButtonStyle())

            if showsDownloadSettings {
                Divider().overlay(Color.mlHairline)
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Toggle(isOn: $viewModel.wifiOnly) {
                        Label("Route data on Wi-Fi only", systemImage: "wifi")
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextPrimary)
                    }
                    .tint(.mlAccent)

                    routingDiagnostics
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

    private var routingDiagnostics: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : Motion.spring) {
                    showsRoutingDiagnostics.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text("Routing diagnostics")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                    Spacer()
                    Text(viewModel.routingDiagnosticsSummary)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                    Image(systemName: "chevron.down")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .rotationEffect(.degrees(showsRoutingDiagnostics ? 180 : 0))
                }
                .frame(minHeight: Layout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(MLPressableButtonStyle())

            if showsRoutingDiagnostics {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    diagnosticDetail(label: "Last pack", value: viewModel.lastRoutingPackText)
                    diagnosticDetail(label: "Last fallback", value: viewModel.lastFallbackText)
                    diagnosticDetail(label: "Last check", value: viewModel.lastRoutingDurationText)
                    Button("Reset diagnostics", systemImage: "arrow.counterclockwise") {
                        Task { await viewModel.resetRoutingDiagnostics() }
                    }
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .frame(minHeight: Layout.minTouchTarget)
                    .buttonStyle(MLPressableButtonStyle())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
        Text("Map data from OpenStreetMap contributors. Map rendering by MapLibre. Offline areas combine locally stored maps with signed road data where available.")
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OfflineAreaSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: OfflineAreasViewModel
    @State private var areaSize = OfflineAreaSize.nearby
    @State private var selectedBounds = OfflineRegionBounds.centered(
        at: Self.initialCenter,
        sideKilometers: OfflineAreaSize.nearby.sideKilometers
    )
    @State private var focusRequest = OfflineMapFocusRequest(
        id: UUID(),
        bounds: OfflineRegionBounds.centered(
            at: Self.initialCenter,
            sideKilometers: OfflineAreaSize.nearby.sideKilometers
        )
    )
    @State private var locateRequestID = UUID()
    @State private var areaName = "Offline Ride Area"

    private static let initialCenter = Coordinate(latitude: -36.65, longitude: 174.785)

    private var draft: OfflineMapAreaDraft {
        OfflineMapAreaDraft(bounds: selectedBounds)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                instruction
                areaSizeControl
                selectionMap
                downloadDetails
                downloadAction
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Choose Area")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isDownloadingMap)
        .interactiveDismissDisabled(viewModel.isDownloadingMap)
    }

    private var instruction: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "hand.draw.fill")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlAccent)
                .frame(width: Spacing.xl)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Move the map over your ride area")
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("The map, available route-planning data, and navigation guidance inside the square are downloaded together.")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
            selectedBounds = bounds
            withAnimation(reduceMotion ? nil : Motion.spring) {
                focusRequest = OfflineMapFocusRequest(id: UUID(), bounds: bounds)
            }
        }
    }

    private var selectionMap: some View {
        OfflineMapSelectionMap(
            selectedBounds: $selectedBounds,
            focusRequest: focusRequest,
            locateRequestID: locateRequestID
        )
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            GeometryReader { proxy in
                let rectangle = OfflineMapSelectionLayout.rectangle(in: proxy.size)
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Color.mlAccent.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .stroke(Color.mlAccent, lineWidth: Layout.hairline * 3)
                    }
                    .frame(width: rectangle.width, height: rectangle.height)
                    .position(x: rectangle.midX, y: rectangle.midY)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: Spacing.sm) {
                Label("Drag to choose", systemImage: "hand.draw.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(minHeight: Layout.minTouchTarget)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button {
                    Haptics.selection()
                    locateRequestID = UUID()
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
        .accessibilityLabel("Map for choosing an offline download area")
        .accessibilityHint("Move and zoom the map. Everything inside the highlighted square will be downloaded.")
    }

    private var downloadDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Name this area").mlKicker()
                TextField("Offline area name", text: $areaName)
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlTextPrimary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(Spacing.md)
                    .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }

            HStack(spacing: Spacing.md) {
                detailMetric(value: viewModel.estimatedDownloadSizeText(for: draft), label: "Estimated")
                Divider().overlay(Color.mlHairline)
                detailMetric(value: includedDataTitle, label: "Includes")
                Divider().overlay(Color.mlHairline)
                detailMetric(value: areaSize.title, label: "Width")
            }
            .frame(minHeight: Spacing.xxl)

            Label(includedDataDetail, systemImage: includedDataSymbol)
                .font(MLFont.caption)
                .foregroundStyle(includedDataColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        }
    }

    @ViewBuilder
    private var downloadAction: some View {
        if viewModel.isDownloadingMap {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(viewModel.downloadStage.title)
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                    Spacer()
                    Text(downloadProgressDetail)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .monospacedDigit()
                }
                if case .map = viewModel.downloadStage {
                    ProgressView(value: viewModel.mapDownloadProgress?.fractionCompleted ?? 0)
                        .tint(.mlAccent)
                } else {
                    ProgressView()
                        .tint(.mlAccent)
                }
                Text(viewModel.downloadStage.detail)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextTertiary)
            }
            .padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else {
            PrimaryButton(
                title: "Download Offline Area",
                systemImage: "arrow.down.circle.fill"
            ) {
                Task { await download() }
            }
            .disabled(areaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func detailMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(MLFont.bodyEmphasised)
                .foregroundStyle(Color.mlTextPrimary)
                .monospacedDigit()
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var includedDataTitle: String {
        viewModel.coverageFraction(for: selectedBounds) > 0.001 ? "Map + routes" : "Map"
    }

    private var includedDataDetail: String {
        let coverage = viewModel.coverageFraction(for: selectedBounds)
        if coverage >= 0.9 {
            return "Route planning and turn-by-turn will work offline throughout this selection."
        }
        if coverage > 0.001 {
            return "The map works throughout this selection; offline routing works inside available road coverage."
        }
        return "The map works offline here. Route-planning data has not been published for this area yet."
    }

    private var includedDataSymbol: String {
        viewModel.coverageFraction(for: selectedBounds) > 0.001
            ? "checkmark.circle.fill"
            : "info.circle.fill"
    }

    private var includedDataColor: Color {
        viewModel.coverageFraction(for: selectedBounds) > 0.001 ? .mlSuccess : .mlInfo
    }

    private var downloadProgressDetail: String {
        switch viewModel.downloadStage {
        case .map:
            return viewModel.mapDownloadProgress?.sizeText ?? "Preparing"
        case .routing:
            return "Signed data"
        case .finalizing:
            return "Almost ready"
        }
    }

    private func download() async {
        let name = areaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if await viewModel.downloadMap(name: name, draft: draft) {
            dismiss()
        }
    }
}

private struct OfflineMapAreaCard: View {
    let area: OfflineMapArea
    let capability: OfflineAreaCapability
    let needsSetup: Bool
    let isCompletingSetup: Bool
    let onResume: () -> Void
    let onCompleteSetup: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(statusColor.opacity(0.12))
                    Image(systemName: statusSymbol)
                        .font(MLFont.headline)
                        .foregroundStyle(statusColor)
                }
                .frame(width: Spacing.xxl, height: Spacing.xxl)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(area.name)
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                        .lineLimit(2)
                    Text(area.status == .complete ? capability.title : area.progressText)
                        .font(MLFont.caption)
                        .foregroundStyle(displayColor)
                    Text("\(area.sizeText) on this iPhone")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: Spacing.xs)
            }

            if area.status != .complete {
                ProgressView(value: area.progress)
                    .tint(.mlAccent)
            }

            HStack(spacing: Spacing.sm) {
                NavigationLink {
                    OfflineMapAreaDetailView(area: area, capability: capability)
                } label: {
                    cardActionLabel("View", symbol: "map.fill", tint: .mlAccent)
                }
                .buttonStyle(MLPressableButtonStyle())

                if needsSetup, area.status == .complete {
                    Button(action: onCompleteSetup) {
                        if isCompletingSetup {
                            ProgressView()
                                .tint(.mlAccent)
                                .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                        } else {
                            cardActionLabel("Finish Setup", symbol: "arrow.down.circle.fill", tint: .mlAccent)
                        }
                    }
                    .buttonStyle(MLPressableButtonStyle())
                    .disabled(isCompletingSetup)
                }

                Menu {
                    if area.status == .paused || area.status == .failed {
                        Button("Resume Download", systemImage: "arrow.clockwise", action: onResume)
                    }
                    Button("Rename", systemImage: "pencil", action: onRename)
                    Button("Remove Download", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextSecondary)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                        .background(Color.mlSurfaceElevated, in: Circle())
                }
                .buttonStyle(MLPressableButtonStyle())
                .accessibilityLabel("More actions for \(area.name)")
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        }
    }

    private var statusColor: Color {
        switch area.status {
        case .complete: .mlSuccess
        case .downloading: .mlAccent
        case .preparing, .paused: .mlWarning
        case .failed: .mlDanger
        }
    }

    private var displayColor: Color {
        guard area.status == .complete else { return statusColor }
        switch capability.level {
        case .complete, .partial: return .mlSuccess
        case .setupAvailable: return .mlWarning
        case .mapOnly: return .mlInfo
        }
    }

    private var statusSymbol: String {
        switch area.status {
        case .complete: "checkmark.circle.fill"
        case .downloading: "arrow.down.circle.fill"
        case .preparing: "clock.fill"
        case .paused: "pause.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func cardActionLabel(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(MLFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Layout.minTouchTarget)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

private struct OfflineMapAreaDetailView: View {
    let area: OfflineMapArea
    let capability: OfflineAreaCapability

    var body: some View {
        ZStack(alignment: .bottom) {
            OfflineMapView(bounds: area.bounds)
                .ignoresSafeArea(edges: .bottom)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(area.name)
                            .font(MLFont.title2)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text(area.status == .complete ? capability.title : area.progressText)
                            .font(MLFont.caption)
                            .foregroundStyle(capabilityColor)
                    }
                    Spacer()
                    Text(area.sizeText)
                        .font(MLFont.monoSmall)
                        .foregroundStyle(Color.mlTextSecondary)
                        .monospacedDigit()
                }

                Label(area.status == .complete ? capability.detail : "Finish this download before relying on it offline.",
                      systemImage: capabilitySymbol)
                .font(MLFont.callout)
                .foregroundStyle(capabilityColor)
            }
            .padding(Spacing.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(Spacing.screenH)
        }
        .background(Color.mlBackground)
        .navigationTitle("Offline Area")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var capabilityColor: Color {
        guard area.status == .complete else { return .mlWarning }
        switch capability.level {
        case .complete, .partial: return .mlSuccess
        case .setupAvailable: return .mlWarning
        case .mapOnly: return .mlInfo
        }
    }

    private var capabilitySymbol: String {
        guard area.status == .complete else { return "exclamationmark.triangle.fill" }
        switch capability.level {
        case .complete, .partial: return "checkmark.circle.fill"
        case .setupAvailable: return "arrow.down.circle.fill"
        case .mapOnly: return "info.circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        OfflineAreasView()
    }
    .preferredColorScheme(.dark)
}
