import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    let email: String?
    let userID: UUID
    let accessToken: @Sendable () async -> String?
    let onSignOut: () -> Void

    @State private var isExporting = false
    @State private var activityPayload: ActivityPayload?
    @State private var errorMessage: String?
    @State private var confirmingSignOut = false
    private let exportService = AccountDataExportService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    accountHeader
                    dataSection
                    sessionSection
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.vertical, Spacing.lg)
            }
            .background(Color.mlBackground)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlAccent)
                }
            }
        }
        .sheet(item: $activityPayload) { payload in
            ActivityView(items: payload.items)
        }
        .confirmationDialog("Sign out of Memory Lanes?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                dismiss()
                onSignOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var accountHeader: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "person.crop.circle.fill")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Rider account").mlKicker()
                Text(email ?? "Signed-in rider")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Data & Privacy").mlKicker()

            VStack(spacing: 0) {
                Button {
                    Task { await exportAccountData() }
                } label: {
                    accountRow(
                        title: "Export account data",
                        detail: "Rides, routes, journal and GPX",
                        symbol: "square.and.arrow.up",
                        trailingSymbol: isExporting ? nil : "chevron.right"
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
                    Divider().overlay(Color.mlHairline)
                    Text(errorMessage)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                }
            }
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Session").mlKicker()

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
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
        }
    }

    private func accountRow(
        title: String,
        detail: String,
        symbol: String,
        trailingSymbol: String?,
        tint: Color = .mlAccent,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(MLFont.headline)
                .foregroundStyle(tint)
                .frame(width: Spacing.xl)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(isDestructive ? Color.mlDanger : Color.mlTextPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
            }

            Spacer()

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
}

#Preview {
    AccountView(
        email: "rider@example.com",
        userID: UUID(),
        accessToken: { "preview-token" },
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}
