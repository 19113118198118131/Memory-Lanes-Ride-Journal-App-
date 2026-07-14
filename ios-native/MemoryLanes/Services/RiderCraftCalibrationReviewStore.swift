import Foundation

protocol RiderCraftCalibrationReviewStoring: Sendable {
    func reviews(for rideID: UUID, thresholdVersion: Int) async throws -> [RiderCraftCalibrationReview]
    func save(_ review: RiderCraftCalibrationReview) async throws
    func makeExportFile() async throws -> URL
}

actor RiderCraftCalibrationReviewStore: RiderCraftCalibrationReviewStoring {
    static let shared = RiderCraftCalibrationReviewStore()

    private struct Archive: Codable {
        let version: Int
        var reviews: [RiderCraftCalibrationReview]

        init(reviews: [RiderCraftCalibrationReview]) {
            version = 1
            self.reviews = reviews
        }
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private var cachedReviews: [RiderCraftCalibrationReview]?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func reviews(for rideID: UUID, thresholdVersion: Int) async throws -> [RiderCraftCalibrationReview] {
        try loadReviews()
            .filter { $0.rideID == rideID && $0.thresholdVersion == thresholdVersion }
            .sorted { $0.replayIndex < $1.replayIndex }
    }

    func save(_ review: RiderCraftCalibrationReview) async throws {
        var reviews = try loadReviews()
        if let index = reviews.firstIndex(where: { $0.id == review.id }) {
            reviews[index] = review
        } else {
            reviews.append(review)
        }
        reviews.sort {
            if $0.rideID == $1.rideID { return $0.replayIndex < $1.replayIndex }
            return $0.rideID.uuidString < $1.rideID.uuidString
        }
        try persist(reviews)
        cachedReviews = reviews
    }

    func makeExportFile() async throws -> URL {
        let archive = Archive(reviews: try loadReviews())
        let data = try Self.encoder.encode(archive)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("rider-craft-calibration-reviews-v1.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func loadReviews() throws -> [RiderCraftCalibrationReview] {
        if let cachedReviews { return cachedReviews }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedReviews = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let archive = try Self.decoder.decode(Archive.self, from: data)
        cachedReviews = archive.reviews
        return archive.reviews
    }

    private func persist(_ reviews: [RiderCraftCalibrationReview]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(Archive(reviews: reviews))
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("MemoryLanes", isDirectory: true)
            .appendingPathComponent("rider-craft-calibration-reviews-v1.json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
