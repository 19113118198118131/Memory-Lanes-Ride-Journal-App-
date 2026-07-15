import UIKit
@preconcurrency import UserNotifications

@MainActor
final class NotificationCoordinator: ObservableObject {
    static let shared = NotificationCoordinator()

    @Published private(set) var deviceToken: String?
    @Published private(set) var registrationError: String?
    @Published var pendingGroupInvite: GroupRideInvite?

    private let center = UNUserNotificationCenter.current()

    private init() {
        UserDefaults.standard.register(defaults: [Self.reminderPreferenceKey: true])
    }

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .enabled
        case .denied:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            registrationError = error.localizedDescription
            return false
        }
    }

    func registerForRemoteNotificationsIfAuthorized() async {
        guard await permissionState() == .enabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func receiveDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        registrationError = nil
    }

    func receiveRegistrationError(_ error: Error) {
        registrationError = error.localizedDescription
    }

    func routeNotification(userInfo: [AnyHashable: Any]) {
        routeNotification(
            deepLink: userInfo["deep_link"] as? String,
            shareToken: userInfo["share_token"] as? String
        )
    }

    func routeNotification(deepLink: String?, shareToken: String?) {
        if let deepLink,
           let url = URL(string: deepLink),
           let invite = GroupRideInvite.parse(url) {
            pendingGroupInvite = invite
            return
        }
        if let shareToken, let token = UUID(uuidString: shareToken) {
            pendingGroupInvite = GroupRideInvite(shareToken: token)
        }
    }

    func reconcileReminder(for groupRide: GroupRide) async {
        let identifier = Self.reminderIdentifier(groupRide.shareToken)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard UserDefaults.standard.bool(forKey: Self.reminderPreferenceKey),
              groupRide.status == .scheduled,
              groupRide.yourRSVP == .going || groupRide.yourRSVP == .maybe,
              let meetTime = groupRide.meetTime,
              meetTime > Date() else { return }

        let preferredReminder = meetTime.addingTimeInterval(-3_600)
        let fallbackReminder = meetTime.addingTimeInterval(-600)
        let fireDate = preferredReminder > Date() ? preferredReminder : fallbackReminder
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = preferredReminder > Date() ? "Ride starts in one hour" : "Ride starts soon"
        content.body = groupRide.meetPoint.map { "\(groupRide.title) meets at \($0)." }
            ?? "\(groupRide.title) is coming up."
        content.sound = .default
        content.threadIdentifier = "group-ride-\(groupRide.id.uuidString)"
        content.userInfo = [
            "deep_link": "memorylanes://group/\(groupRide.shareToken.uuidString)",
            "share_token": groupRide.shareToken.uuidString
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    func setRideRemindersEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.reminderPreferenceKey)
        if !enabled {
            Task { @MainActor in
                let requests = await center.pendingNotificationRequests()
                let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }

    func clearLocalStateForSignOut() async {
        let requests = await center.pendingNotificationRequests()
        let reminderIdentifiers = requests.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: reminderIdentifiers)
        UIApplication.shared.unregisterForRemoteNotifications()
        deviceToken = nil
        registrationError = nil
        pendingGroupInvite = nil
    }

    static var pushEnvironment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    private static let reminderPrefix = "memorylanes.group-reminder."
    private static let reminderPreferenceKey = "memorylanes.notifications.ride-reminders"

    private static func reminderIdentifier(_ token: UUID) -> String {
        reminderPrefix + token.uuidString
    }
}

final class MemoryLanesAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationCoordinator.shared.receiveDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationCoordinator.shared.receiveRegistrationError(error)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let deepLink = userInfo["deep_link"] as? String
        let shareToken = userInfo["share_token"] as? String
        await MainActor.run {
            NotificationCoordinator.shared.routeNotification(deepLink: deepLink, shareToken: shareToken)
        }
    }
}
