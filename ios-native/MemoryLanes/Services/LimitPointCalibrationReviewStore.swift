import Foundation

protocol LimitPointCalibrationReviewStoring: Sendable {
    func reviews(for rideID: UUID, modelVersion: Int) async throws -> [LimitPointCalibrationReview]
    func allReviews(modelVersion: Int) async throws -> [LimitPointCalibrationReview]
    func save(_ review: LimitPointCalibrationReview) async throws
    func removeReview(for rideID: UUID, modelVersion: Int, cornerID: Int) async throws
    func resetReviews(for rideID: UUID, modelVersion: Int) async throws
}

actor LimitPointCalibrationReviewStore: LimitPointCalibrationReviewStoring {
    static let shared = LimitPointCalibrationReviewStore()

    private struct Archive: Codable {
        let version: Int
        var reviews: [LimitPointCalibrationReview]

        init(reviews: [LimitPointCalibrationReview]) {
            version = 1
            self.reviews = reviews
        }
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private var cachedReviews: [LimitPointCalibrationReview]?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func reviews(for rideID: UUID, modelVersion: Int) async throws -> [LimitPointCalibrationReview] {
        try loadReviews()
            .filter { $0.rideID == rideID && $0.modelVersion == modelVersion }
            .sorted { $0.replayIndex < $1.replayIndex }
    }

    func allReviews(modelVersion: Int) async throws -> [LimitPointCalibrationReview] {
        try loadReviews().filter { $0.modelVersion == modelVersion }
    }

    func save(_ review: LimitPointCalibrationReview) async throws {
        var reviews = try loadReviews()
        if let index = reviews.firstIndex(where: { $0.id == review.id }) {
            reviews[index] = review
        } else {
            reviews.append(review)
        }
        try persist(reviews)
        cachedReviews = reviews
    }

    func removeReview(for rideID: UUID, modelVersion: Int, cornerID: Int) async throws {
        var reviews = try loadReviews()
        reviews.removeAll {
            $0.rideID == rideID && $0.modelVersion == modelVersion && $0.cornerID == cornerID
        }
        try persist(reviews)
        cachedReviews = reviews
    }

    func resetReviews(for rideID: UUID, modelVersion: Int) async throws {
        var reviews = try loadReviews()
        reviews.removeAll { $0.rideID == rideID && $0.modelVersion == modelVersion }
        try persist(reviews)
        cachedReviews = reviews
    }

    private func loadReviews() throws -> [LimitPointCalibrationReview] {
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

    private func persist(_ reviews: [LimitPointCalibrationReview]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(Archive(reviews: reviews)).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("MemoryLanes", isDirectory: true)
            .appendingPathComponent("limit-point-calibration-reviews-v1.json")
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
