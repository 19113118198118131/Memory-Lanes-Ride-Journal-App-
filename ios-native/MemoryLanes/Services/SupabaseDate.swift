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
        return fractionalFormatter().date(from: string)
            ?? plainFormatter().date(from: string)
            ?? dateOnlyFormatter().date(from: string)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func dateOnlyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
