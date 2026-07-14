import SwiftUI
import UniformTypeIdentifiers

struct GPXImportView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AuthSession
    let accessToken: @Sendable () async -> String?
    let onSaved: (Ride) -> Void

    @State private var showingImporter = false
    @State private var title = ""
    @State private var selectedFileName: String?
    @State private var gpxData: Data?
    @State private var track: GPXTrack?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let parser = GPXParser()
    private let importService = RideImportService()

    init(
        session: AuthSession,
        accessToken: @escaping @Sendable () async -> String?,
        onSaved: @escaping (Ride) -> Void
    ) {
        self.session = session
        self.accessToken = accessToken
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    pickerCard
                    if let track {
                        preview(track)
                        titleCard
                        saveActions
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlDanger)
                            .padding(Spacing.md)
                            .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                }
                .padding(.vertical, Spacing.md)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle("Import GPX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.gpx, .xml],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("GPX import").mlKicker()
            Text("Bring in a ride")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Choose a GPX file from Files. Memory Lanes will parse the track, preview the route, and save it to your ride journal.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "doc.badge.plus")
                    .font(MLFont.displaySmall)
                    .foregroundStyle(Color.mlAccent)
                    .frame(width: 52, height: 52)
                    .background(Color.mlAccent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(selectedFileName ?? "No file selected")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("GPX files up to 5 MB")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
            }
            SecondaryButton(title: "Choose GPX File", systemImage: "folder") {
                showingImporter = true
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func preview(_ track: GPXTrack) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Preview")
            RouteThumbnail(route: track.routePreview)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                StatCard(label: "Distance", value: String(format: "%.1f", track.distanceMeters / 1000), unit: "km", systemImage: "map")
                StatCard(label: "Time", value: formattedDuration(track.durationSeconds), systemImage: "clock")
                StatCard(label: "Elevation", value: String(format: "%.0f", track.elevationGainMeters), unit: "m", systemImage: "mountain.2.fill")
                StatCard(label: "Points", value: "\(track.points.count)", systemImage: "location.fill")
            }
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Ride title").mlKicker()
            TextField("Sunday ride", text: $title)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(height: 52)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                )
        }
    }

    private var saveActions: some View {
        PrimaryButton(title: "Save to Journal", systemImage: "tray.and.arrow.down.fill", isLoading: isSaving) {
            Task { await save() }
        }
        .disabled(!canSave)
    }

    private var canSave: Bool {
        track != nil && gpxData != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.pathExtension.lowercased() == "gpx" || url.pathExtension.lowercased() == "xml" else {
                throw GPXImportViewError.unsupportedFile
            }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024 else { throw GPXImportViewError.fileTooLarge }
            let parsed = try parser.parse(data: data)
            selectedFileName = url.lastPathComponent
            title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
            gpxData = data
            track = parsed
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let gpxData, let track else { return }
        isSaving = true
        errorMessage = nil
        do {
            guard let token = await accessToken() else { throw RideImportError.notAuthenticated }
            let saved = try await importService.saveImportedRide(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                gpxData: gpxData,
                track: track,
                userID: session.userID,
                accessToken: token
            )
            Haptics.success()
            onSaved(saved)
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private enum GPXImportViewError: LocalizedError {
    case unsupportedFile
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Choose a .gpx file."
        case .fileTooLarge:
            return "GPX file is too large. The limit is 5 MB."
        }
    }
}

private extension UTType {
    static let gpx = UTType(filenameExtension: "gpx") ?? .xml
}

#Preview {
    GPXImportView(
        session: AuthSession(accessToken: "", refreshToken: "", expiresAt: Date().addingTimeInterval(3600), userID: UUID(), email: "preview@example.com"),
        accessToken: { "" },
        onSaved: { _ in }
    )
    .preferredColorScheme(.dark)
}
