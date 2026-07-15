import Observation
import SwiftUI

@MainActor
@Observable
final class RiderProfileEditorViewModel {
    var displayName: String
    var region: String
    private(set) var isSaving = false
    var errorMessage: String?

    private let service: RiderProfileServing

    init(profile: RiderProfile?, fallbackName: String, service: RiderProfileServing) {
        displayName = profile?.displayName.nilIfBlank ?? fallbackName
        region = profile?.region ?? ""
        self.service = service
    }

    var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    func save() async -> RiderProfile? {
        guard canSave else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            return try await service.saveProfile(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                region: region.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct RiderProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: RiderProfileEditorViewModel

    let onSaved: (RiderProfile) -> Void

    init(viewModel: RiderProfileEditorViewModel, onSaved: @escaping (RiderProfile) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Community identity").mlKicker()
                        Text("How riders see you")
                            .font(MLFont.display)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text("Shown only when you host or join a group ride. Your email and ride history stay private.")
                            .font(MLFont.body)
                            .foregroundStyle(Color.mlTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .mlStaggeredReveal(index: 0)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        profileField(title: "Display name", prompt: "Rider name", text: $viewModel.displayName)
                        Divider().overlay(Color.mlHairline)
                        profileField(title: "Region", prompt: "Auckland", text: $viewModel.region)
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                    }
                    .mlStaggeredReveal(index: 1)

                    Label("Region helps riders understand where a community ride is based. It is optional and can be changed anytime.", systemImage: "hand.raised.fill")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .padding(Spacing.md)
                        .background(Color.mlAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card))
                        .mlStaggeredReveal(index: 2)

                    if let errorMessage = viewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlDanger)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    PrimaryButton(title: "Save Profile", systemImage: "checkmark", isLoading: viewModel.isSaving) {
                        Task {
                            guard let profile = await viewModel.save() else {
                                Haptics.error()
                                return
                            }
                            Haptics.success()
                            onSaved(profile)
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .mlStaggeredReveal(index: 3)
                }
                .padding(.vertical, Spacing.md)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle("Rider Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .animation(reduceMotion ? nil : Motion.spring, value: viewModel.errorMessage)
        }
        .preferredColorScheme(.dark)
    }

    private func profileField(title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).mlKicker()
            TextField(prompt, text: text)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.vertical, Spacing.xs)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
