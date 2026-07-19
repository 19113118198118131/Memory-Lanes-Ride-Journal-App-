import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let email: String?
    let userID: UUID
    let accessToken: @Sendable () async -> String?
    let onSignOut: () -> Void

    @State private var library = AccountLibrarySummary()
    @State private var offlineLibrary = AccountOfflineLibrarySummary()
    @State private var riderProfile: RiderProfile?
    @State private var isExporting = false
    @State private var activityPayload: ActivityPayload?
    @State private var errorMessage: String?
    @State private var confirmingSignOut = false
    @State private var showingProfileEditor = false
    private let exportService = AccountDataExportService()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    profileHeader
                        .mlStaggeredReveal(index: 0)
                    libraryOverview
                        .mlStaggeredReveal(index: 1)
                    riderAndCommunitySection
                        .mlStaggeredReveal(index: 2)
                    librarySection
                        .mlStaggeredReveal(index: 3)
                    dataSection
                        .mlStaggeredReveal(index: 4)
                    appSection
                        .mlStaggeredReveal(index: 5)
                    sessionSection
                        .mlStaggeredReveal(index: 6)
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.vertical, Spacing.lg)
            }
            .background(Color.mlBackground)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextPrimary)
                            .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                            .background(Color.mlSurface, in: Circle())
                    }
                    .buttonStyle(MLPressableButtonStyle())
                    .accessibilityLabel("Close account")
                }
            }
        }
        .task {
            async let libraryTask: Void = loadLocalLibrary()
            async let profileTask: Void = loadRiderProfile()
            _ = await (libraryTask, profileTask)
        }
        .onAppear {
            Task { await loadOfflineLibrary() }
        }
        .sheet(item: $activityPayload) { payload in
            ActivityView(items: payload.items)
        }
        .sheet(isPresented: $showingProfileEditor) {
            RiderProfileEditorView(
                viewModel: RiderProfileEditorViewModel(
                    profile: riderProfile,
                    fallbackName: fallbackDisplayName,
                    service: riderProfileService
                )
            ) { profile in
                withAnimation(reduceMotion ? nil : Motion.springGentle) {
                    riderProfile = profile
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Sign out of Memory Lanes?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                dismiss()
                onSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rides stored in your account will remain available when you sign in again.")
        }
    }

    private var profileHeader: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.mlAccent.opacity(0.14))
                Circle()
                    .stroke(Color.mlAccent.opacity(0.45), lineWidth: Layout.hairline)
                Text(initials)
                    .font(MLFont.displaySmall)
                    .foregroundStyle(Color.mlAccent)
            }
            .frame(width: Layout.accountAvatarSize, height: Layout.accountAvatarSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Rider profile").mlKicker()
                Text(displayName)
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(1)
                Text(email ?? "Signed-in rider")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let region = riderProfile?.region, !region.isEmpty {
                    Label(region, systemImage: "mappin.and.ellipse")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            ViewThatFits(in: .horizontal) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(MLFont.kicker)
                    .foregroundStyle(Color.mlSuccess)
                    .padding(.horizontal, Spacing.xs)
                    .frame(minHeight: Layout.minTouchTarget)
                    .background(Color.mlSuccess.opacity(0.10), in: Capsule())

                Image(systemName: "checkmark.circle.fill")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlSuccess)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .accessibilityLabel("Cloud account connected")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryOverview: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    libraryMetric(value: "\(library.rideCount)", label: "Rides")
                    Divider().overlay(Color.mlHairline)
                    libraryMetric(value: library.distanceText, label: "Distance")
                    Divider().overlay(Color.mlHairline)
                    libraryMetric(value: "\(offlineLibrary.areaCount)", label: "Offline")
                }
            } else {
                HStack(spacing: 0) {
                    libraryMetric(value: "\(library.rideCount)", label: "Rides")
                    metricDivider
                    libraryMetric(value: library.distanceText, label: "Distance")
                    metricDivider
                    libraryMetric(value: "\(offlineLibrary.areaCount)", label: "Offline")
                }
            }
        }
        .padding(.vertical, Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.mlHairline)
            .frame(width: Layout.hairline, height: Spacing.xl)
    }

    private func libraryMetric(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(MLFont.displaySmall)
                .foregroundStyle(Color.mlTextPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
    }

    private var librarySection: some View {
        accountSection(title: "Library & Sync") {
            statusRow(
                title: "Cloud sync",
                detail: "Supabase account connected",
                symbol: "arrow.triangle.2.circlepath.icloud",
                status: "On",
                statusTint: .mlSuccess
            )
            rowDivider
            statusRow(
                title: "On this iPhone",
                detail: library.localLibraryDetail,
                symbol: "iphone",
                status: nil
            )
            rowDivider
            NavigationLink {
                OfflineAreasView()
            } label: {
                accountRow(
                    title: "Offline Areas",
                    detail: offlineLibrary.detail,
                    symbol: "map.fill",
                    trailingSymbol: "chevron.right",
                    trailingText: offlineLibrary.statusText
                )
            }
            .buttonStyle(MLPressableButtonStyle())
        }
    }

    private var riderAndCommunitySection: some View {
        accountSection(
            title: "Rider & Community",
            footer: "Only your display name and region appear on group rides. Your email and ride library remain private."
        ) {
            Button {
                showingProfileEditor = true
            } label: {
                accountRow(
                    title: "Rider profile",
                    detail: riderProfile?.region.isEmpty == false
                        ? "\(displayName) · \(riderProfile?.region ?? "")"
                        : displayName,
                    symbol: "person.crop.circle.badge.checkmark",
                    trailingSymbol: "chevron.right"
                )
            }
            .buttonStyle(MLPressableButtonStyle())
            rowDivider
            NavigationLink {
                NotificationSettingsView(
                    viewModel: NotificationSettingsViewModel(
                        service: NotificationService(accessToken: accessToken)
                    )
                )
            } label: {
                accountRow(
                    title: "Ride notifications",
                    detail: "Invites, RSVPs and pre-ride reminders",
                    symbol: "bell.badge",
                    trailingSymbol: "chevron.right"
                )
            }
            .buttonStyle(MLPressableButtonStyle())
        }
    }

    private var dataSection: some View {
        accountSection(title: "Data & Privacy", footer: "Your export includes rides, routes, journal entries and GPX files.") {
            Button {
                Task { await exportAccountData() }
            } label: {
                accountRow(
                    title: "Export account data",
                    detail: "Create a portable copy",
                    symbol: "square.and.arrow.up",
                    trailingSymbol: nil,
                    trailingText: isExporting ? nil : "Export",
                    trailingTextTint: .mlAccent
                )
                .overlay(alignment: .trailing) {
                    if isExporting {
                        ProgressView()
                            .tint(.mlAccent)
                            .padding(.trailing, Spacing.md)
                    }
                }
            }
            .buttonStyle(MLPressableButtonStyle())
            .disabled(isExporting)

            if let errorMessage {
                rowDivider
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var appSection: some View {
        accountSection(title: "Memory Lanes") {
            statusRow(
                title: "App version",
                detail: "Native iOS",
                symbol: "app.badge.checkmark",
                status: appVersion
            )
        }
    }

    private var sessionSection: some View {
        accountSection(title: "Session") {
            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                accountRow(
                    title: "Sign out",
                    detail: "",
                    symbol: "rectangle.portrait.and.arrow.right",
                    trailingSymbol: nil,
                    tint: .mlDanger,
                    isDestructive: true
                )
            }
            .buttonStyle(MLPressableButtonStyle())
        }
    }

    private func accountSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).mlKicker()
            VStack(spacing: 0) { content() }
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                }
            if let footer {
                Text(footer)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextTertiary)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private func statusRow(
        title: String,
        detail: String,
        symbol: String,
        status: String?,
        statusTint: Color = .mlTextSecondary
    ) -> some View {
        accountRow(
            title: title,
            detail: detail,
            symbol: symbol,
            trailingSymbol: nil,
            trailingText: status,
            trailingTextTint: statusTint
        )
    }

    private func accountRow(
        title: String,
        detail: String,
        symbol: String,
        trailingSymbol: String?,
        trailingText: String? = nil,
        trailingTextTint: Color = .mlTextSecondary,
        tint: Color = .mlAccent,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: symbol)
                    .font(MLFont.headline)
                    .foregroundStyle(tint)
            }
            .frame(width: Spacing.xl, height: Spacing.xl)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(isDestructive ? Color.mlDanger : Color.mlTextPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Spacing.sm)

            if let trailingText {
                Text(trailingText)
                    .font(MLFont.callout)
                    .foregroundStyle(trailingTextTint)
                    .lineLimit(1)
            }
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextTertiary)
            }
        }
        .padding(Spacing.md)
        .frame(minHeight: Spacing.xxl + Spacing.lg)
        .contentShape(Rectangle())
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.mlHairline)
            .padding(.leading, Spacing.xxl + Spacing.md)
    }

    @MainActor
    private func loadLocalLibrary() async {
        let rides = await RideLocalStore.shared.rides(for: userID)
        withAnimation(reduceMotion ? nil : Motion.springGentle) {
            library = AccountLibrarySummary(rides: rides)
        }
    }

    @MainActor
    private func loadOfflineLibrary() async {
        let regions = await OfflineRegionStore.shared.installedRegions()
        let byteCount = regions.reduce(Int64(0)) { $0 + $1.descriptor.byteCount }
        withAnimation(reduceMotion ? nil : Motion.springGentle) {
            offlineLibrary = AccountOfflineLibrarySummary(
                areaCount: regions.count,
                byteCount: byteCount
            )
        }
    }

    @MainActor
    private func loadRiderProfile() async {
        do {
            let profile = try await riderProfileService.fetchProfile()
            withAnimation(reduceMotion ? nil : Motion.springGentle) {
                riderProfile = profile
            }
        } catch {
            // Profile identity is optional; account and solo riding remain available.
        }
    }

    @MainActor
    private func exportAccountData() async {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
            let url = try await exportService.makeExport(
                userID: userID,
                email: email,
                accessToken: token
            )
            Haptics.success()
            activityPayload = ActivityPayload(items: [url])
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }

    private var displayName: String {
        if let profileName = riderProfile?.displayName,
           !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return profileName
        }
        return fallbackDisplayName
    }

    private var fallbackDisplayName: String {
        guard let localPart = email?.split(separator: "@").first else { return "Rider" }
        let words = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
        let name = words.map { $0.capitalized }.joined(separator: " ")
        return name.isEmpty ? "Rider" : name
    }

    private var riderProfileService: RiderProfileServing {
        RiderProfileService(accessToken: accessToken, userID: userID)
    }

    private var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "R" : String(letters).uppercased()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct AccountLibrarySummary {
    var rideCount = 0
    var distanceMeters: Double = 0

    init(rides: [Ride] = []) {
        rideCount = rides.count
        distanceMeters = rides.reduce(0) { $0 + $1.distanceMeters }
    }

    var distanceText: String {
        let kilometers = distanceMeters / 1_000
        return kilometers >= 1_000
            ? String(format: "%.1fk", kilometers / 1_000)
            : String(format: "%.0f km", kilometers)
    }

    var localLibraryDetail: String {
        switch rideCount {
        case 0: "Ready for your first synced ride"
        case 1: "1 ride record cached locally"
        default: "\(rideCount) ride records cached locally"
        }
    }
}

private struct AccountOfflineLibrarySummary {
    var areaCount = 0
    var byteCount: Int64 = 0

    var statusText: String? {
        areaCount == 0 ? nil : "\(areaCount) ready"
    }

    var detail: String {
        guard areaCount > 0 else {
            return "Download roads for local planning and navigation"
        }
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        return "\(size) of road data available without a connection"
    }
}

#Preview {
    AccountView(
        email: "samar.sharma@example.com",
        userID: UUID(),
        accessToken: { "preview-token" },
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}
