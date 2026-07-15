import Foundation

protocol NotificationServing: Sendable {
    func fetchPreferences() async throws -> NotificationPreferences
    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences
    func registerDevice(token: String, environment: String) async throws
    func removeDevice(token: String) async throws
}

struct NotificationService: NotificationServing, Sendable {
    var client = SupabaseHTTPClient()
    var accessToken: @Sendable () async -> String?

    func fetchPreferences() async throws -> NotificationPreferences {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let preferences: NotificationPreferences? = try await client.post(
            path: "rest/v1/rpc/get_notification_preferences",
            body: NotificationEmptyPayload(),
            accessToken: token
        )
        return preferences ?? NotificationPreferences()
    }

    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let saved: NotificationPreferences? = try await client.post(
            path: "rest/v1/rpc/set_notification_preferences",
            body: NotificationPreferencesPayload(preferences: preferences),
            accessToken: token
        )
        guard let saved else { throw NotificationServiceError.unavailable }
        return saved
    }

    func registerDevice(token deviceToken: String, environment: String) async throws {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let _: UUID? = try await client.post(
            path: "rest/v1/rpc/register_push_device",
            body: PushDevicePayload(
                deviceToken: deviceToken,
                pushEnvironment: environment,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                timezone: TimeZone.current.identifier
            ),
            accessToken: token
        )
    }

    func removeDevice(token deviceToken: String) async throws {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let _: Bool = try await client.post(
            path: "rest/v1/rpc/remove_push_device",
            body: RemovePushDevicePayload(deviceToken: deviceToken),
            accessToken: token
        )
    }
}

enum NotificationServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Notification preferences are temporarily unavailable. Try again shortly."
    }
}

private struct NotificationEmptyPayload: Encodable {}

private struct NotificationPreferencesPayload: Encodable {
    let eventUpdates: Bool
    let rsvpUpdates: Bool
    let rideReminders: Bool
    let quietHours: Bool
    let timezone: String

    init(preferences: NotificationPreferences) {
        eventUpdates = preferences.eventUpdates
        rsvpUpdates = preferences.rsvpUpdates
        rideReminders = preferences.rideReminders
        quietHours = preferences.quietHours
        timezone = TimeZone.current.identifier
    }

    enum CodingKeys: String, CodingKey {
        case eventUpdates = "p_event_updates"
        case rsvpUpdates = "p_rsvp_updates"
        case rideReminders = "p_ride_reminders"
        case quietHours = "p_quiet_hours"
        case timezone = "p_timezone"
    }
}

private struct PushDevicePayload: Encodable {
    let deviceToken: String
    let pushEnvironment: String
    let appVersion: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case deviceToken = "p_device_token"
        case pushEnvironment = "p_push_environment"
        case appVersion = "p_app_version"
        case timezone = "p_timezone"
    }
}

private struct RemovePushDevicePayload: Encodable {
    let deviceToken: String

    enum CodingKeys: String, CodingKey {
        case deviceToken = "p_device_token"
    }
}
