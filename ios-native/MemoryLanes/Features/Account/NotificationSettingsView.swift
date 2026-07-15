import SwiftUI
import UIKit

@MainActor
@Observable
final class NotificationSettingsViewModel {
    private(set) var preferences = NotificationPreferences()
    private(set) var permissionState: NotificationPermissionState = .unknown
    private(set) var isLoading = true
    private(set) var isSaving = false
    var errorMessage: String?

    private let service: NotificationServing
    private let coordinator: NotificationCoordinator

    init(
        service: NotificationServing,
        coordinator: NotificationCoordinator = .shared
    ) {
        self.service = service
        self.coordinator = coordinator
    }

    func load() async {
        isLoading = true
        async let state = coordinator.permissionState()
        async let stored = service.fetchPreferences()
        permissionState = await state
        do {
            preferences = try await stored
            coordinator.setRideRemindersEnabled(preferences.rideReminders)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refreshPermissionState() async {
        permissionState = await coordinator.permissionState()
    }

    func requestPermission() async {
        let granted = await coordinator.requestPermission()
        permissionState = await coordinator.permissionState()
        if granted, let token = coordinator.deviceToken {
            try? await service.registerDevice(
                token: token,
                environment: NotificationCoordinator.pushEnvironment
            )
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func setEventUpdates(_ enabled: Bool) async {
        let previous = preferences
        preferences.eventUpdates = enabled
        await save(revertingTo: previous)
    }

    func setRSVPUpdates(_ enabled: Bool) async {
        let previous = preferences
        preferences.rsvpUpdates = enabled
        await save(revertingTo: previous)
    }

    func setRideReminders(_ enabled: Bool) async {
        let previous = preferences
        preferences.rideReminders = enabled
        coordinator.setRideRemindersEnabled(enabled)
        await save(revertingTo: previous)
    }

    func setQuietHours(_ enabled: Bool) async {
        let previous = preferences
        preferences.quietHours = enabled
        await save(revertingTo: previous)
    }

    private func save(revertingTo previous: NotificationPreferences) async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            preferences.timezone = TimeZone.current.identifier
            preferences = try await service.savePreferences(preferences)
            Haptics.selection()
        } catch {
            preferences = previous
            coordinator.setRideRemindersEnabled(previous.rideReminders)
            errorMessage = error.localizedDescription
            Haptics.error()
        }
        isSaving = false
    }
}

struct NotificationSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: NotificationSettingsViewModel

    init(viewModel: NotificationSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                permissionCard
                    .mlStaggeredReveal(index: 0)

                preferenceSection
                    .mlStaggeredReveal(index: 1)

                quietHoursSection
                    .mlStaggeredReveal(index: 2)

                privacyNote
                    .mlStaggeredReveal(index: 3)

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlDanger)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.mlDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.mlBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshPermissionState() }
        }
        .animation(reduceMotion ? nil : Motion.spring, value: viewModel.errorMessage)
    }

    private var permissionCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: viewModel.permissionState.symbol)
                .font(MLFont.displaySmall)
                .foregroundStyle(permissionTint)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(permissionTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Ride notifications")
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(viewModel.permissionState.title)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            Spacer(minLength: Spacing.sm)

            if viewModel.permissionState != .enabled {
                Button(viewModel.permissionState == .denied ? "Settings" : "Enable") {
                    Task {
                        if viewModel.permissionState == .denied {
                            viewModel.openSystemSettings()
                        } else {
                            await viewModel.requestPermission()
                        }
                    }
                }
                .font(MLFont.callout)
                .foregroundStyle(Color.mlAccent)
                .frame(minHeight: Layout.minTouchTarget)
                .buttonStyle(MLPressableButtonStyle())
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(permissionTint.opacity(0.28), lineWidth: Layout.hairline)
        }
    }

    private var preferenceSection: some View {
        settingsSection(
            title: "Group rides",
            footer: "You can change these at any time. Important event cancellations remain visible inside the app."
        ) {
            notificationToggle(
                title: "Event updates",
                detail: "Time, meeting point and cancellation changes",
                symbol: "calendar.badge.exclamationmark",
                isOn: viewModel.preferences.eventUpdates,
                action: viewModel.setEventUpdates
            )
            rowDivider
            notificationToggle(
                title: "RSVP activity",
                detail: "Responses to rides you organise",
                symbol: "person.2.badge.gearshape",
                isOn: viewModel.preferences.rsvpUpdates,
                action: viewModel.setRSVPUpdates
            )
            rowDivider
            notificationToggle(
                title: "Ride reminders",
                detail: "One hour before rides you may attend",
                symbol: "bell.badge",
                isOn: viewModel.preferences.rideReminders,
                action: viewModel.setRideReminders
            )
        }
    }

    private var quietHoursSection: some View {
        settingsSection(
            title: "Quiet hours",
            footer: "Routine remote updates wait until morning. Cancellations and locally scheduled ride reminders are not delayed."
        ) {
            notificationToggle(
                title: "Quiet overnight",
                detail: "Hold routine updates from 10 pm to 7 am",
                symbol: "moon.zzz.fill",
                isOn: viewModel.preferences.quietHours,
                action: viewModel.setQuietHours
            )
        }
    }

    private var privacyNote: some View {
        Label {
            Text("Memory Lanes stores a rotating device token for delivery. It never exposes your email, location or ride library to other riders.")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Color.mlAccent)
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String,
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
            Text(footer)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
                .padding(.horizontal, Spacing.xs)
        }
    }

    private func notificationToggle(
        title: String,
        detail: String,
        symbol: String,
        isOn: Bool,
        action: @escaping (Bool) async -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in Task { await action(newValue) } }
        )) {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlAccent)
                    .frame(width: Spacing.xl)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(detail)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(.mlAccent)
        .padding(Spacing.md)
        .frame(minHeight: Spacing.xxl + Spacing.lg)
        .disabled(viewModel.isLoading || viewModel.isSaving)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.mlHairline)
            .padding(.leading, Spacing.xxl + Spacing.sm)
    }

    private var permissionTint: Color {
        switch viewModel.permissionState {
        case .enabled: .mlSuccess
        case .denied: .mlWarning
        case .unknown: .mlAccent
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(
            viewModel: NotificationSettingsViewModel(
                service: PreviewNotificationService()
            )
        )
    }
    .preferredColorScheme(.dark)
}

private struct PreviewNotificationService: NotificationServing {
    func fetchPreferences() async throws -> NotificationPreferences { NotificationPreferences() }
    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences { preferences }
    func registerDevice(token: String, environment: String) async throws {}
    func removeDevice(token: String) async throws {}
}
