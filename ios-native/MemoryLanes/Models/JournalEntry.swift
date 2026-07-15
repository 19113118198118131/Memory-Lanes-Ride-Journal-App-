import Foundation

struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var note: String
    var ride: Ride
    var rideDate: Date
    var index: Int
    var coordinate: Coordinate?
    var speedKmh: Double?
    var elevationMeters: Double?

    var displayTitle: String {
        title.isEmpty ? "Moment \(index + 1)" : title
    }

    var displayNote: String {
        note.isEmpty ? "No note yet." : note
    }

    var relativeDate: String {
        rideDate.formatted(.relative(presentation: .named))
    }
}
