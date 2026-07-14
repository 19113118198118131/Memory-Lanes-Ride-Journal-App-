import Foundation

// MARK: - SupabaseDate
//
// Postgres `timestamptz` values come back with fractional seconds
// (e.g. "2026-07-13T12:34:56.789123+00:00"), which a default
// `ISO8601DateFormatter` does NOT parse — it only understands whole seconds.
// Left unhandled, every such timestamp silently fell through to "now".
//
// This parser tries, in order: internet date-time with fractional seconds,
// then without, then a bare calendar date (for `date` columns like ride_date).
// Formatters are cached and are safe to reuse across threads for parsing.

enum SupabaseDate {
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return fractional.date(from: string)
            ?? plain.date(from: string)
            ?? dateOnly.date(from: string)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
