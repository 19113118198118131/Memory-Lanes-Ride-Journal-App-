import Foundation

struct NotificationPreferences: Codable, Equatable, Sendable {
    var eventUpdates: Bool = true
    var rsvpUpdates: Bool = true
    var rideReminders: Bool = true
    var quietHours: Bool = true
    var timezone: String = TimeZone.current.identifier
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case eventUpdates = "event_updates"
        case rsvpUpdates = "rsvp_updates"
        case rideReminders = "ride_reminders"
        case quietHours = "quiet_hours"
        case timezone
        case updatedAt = "updated_at"
    }
}

enum NotificationPermissionState: Equatable, Sendable {
    case unknown
    case denied
    case enabled

    var title: String {
        switch self {
        case .unknown: "Not configured"
        case .denied: "Off in Settings"
        case .enabled: "Enabled"
        }
    }

    var symbol: String {
        switch self {
        case .unknown: "bell.badge"
        case .denied: "bell.slash.fill"
        case .enabled: "bell.badge.fill"
        }
    }
}
