import Foundation

protocol RideLocalStoring: Sendable {
    func rides(for userID: UUID) async -> [Ride]
    func replaceRides(_ rides: [Ride], for userID: UUID) async throws -> [Ride]
    func upsert(_ ride: Ride, gpxData: Data?, for userID: UUID) async throws
    func gpxData(for ride: Ride, userID: UUID) async -> Data?
    func storeGPX(_ data: Data, for ride: Ride, userID: UUID) async throws
    func parsedTrack(for ride: Ride, userID: UUID) async -> GPXTrack?
    func storeParsedTrack(_ track: GPXTrack, for ride: Ride, userID: UUID) async throws
    func detail(for ride: Ride, userID: UUID, analysisVersion: Int) async -> RideDetail?
    func storeDetail(_ detail: RideDetail, for ride: Ride, userID: UUID, analysisVersion: Int) async throws
    func journalEntries(for userID: UUID) async -> [JournalEntry]
    func replaceJournalEntries(_ entries: [JournalEntry], for userID: UUID) async throws
}

actor RideLocalStore: RideLocalStoring {
    static let shared = RideLocalStore()

    private struct Archive: Codable {
        let version: Int
        var entries: [Entry]

        init(entries: [Entry]) {
            version = 1
            self.entries = entries
        }
    }

    private struct Entry: Codable {
        var ride: Ride
        var gpxPath: String?
        var hasGPX: Bool
        var hasParsedTrack: Bool
        var detailVersion: Int?
    }

    private struct ParsedTrackArchive: Codable {
        let version: Int
        let gpxPath: String?
        let points: [RecordingPoint]

        init(gpxPath: String?, points: [RecordingPoint]) {
            version = 1
            self.gpxPath = gpxPath
            self.points = points
        }
    }

    private struct DetailArchive: Codable {
        let version: Int
        let gpxPath: String?
        let detail: RideDetail
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private var archives: [UUID: Archive] = [:]
    private var journalArchives: [UUID: [JournalEntry]] = [:]

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.rootURL = rootURL
            ?? applicationSupport
                .appendingPathComponent("MemoryLanes", isDirectory: true)
                .appendingPathComponent("RideLibrary", isDirectory: true)
    }

    func rides(for userID: UUID) async -> [Ride] {
        let archive = loadArchive(for: userID)
        return archive.entries
            .map(\.ride)
            .sorted { $0.date > $1.date }
    }

    func replaceRides(_ rides: [Ride], for userID: UUID) async throws -> [Ride] {
        let existing = Dictionary(uniqueKeysWithValues: loadArchive(for: userID).entries.map { ($0.ride.id, $0) })
        let remoteIDs = Set(rides.map(\.id))

        for staleID in existing.keys where !remoteIDs.contains(staleID) {
            try? fileManager.removeItem(at: rideDirectory(for: staleID, userID: userID))
        }

        let entries = rides.map { remoteRide -> Entry in
            guard let cached = existing[remoteRide.id], cached.gpxPath == remoteRide.gpxPath else {
                if existing[remoteRide.id] != nil {
                    try? fileManager.removeItem(at: rideDirectory(for: remoteRide.id, userID: userID))
                }
                return Entry(
                    ride: remoteRide,
                    gpxPath: remoteRide.gpxPath,
                    hasGPX: false,
                    hasParsedTrack: false,
                    detailVersion: nil
                )
            }

            var merged = remoteRide
            if merged.routePreview.count <= 1 {
                merged.routePreview = cached.ride.routePreview
            }
            if cached.ride.source == .live {
                merged.source = .live
            }
            return Entry(
                ride: merged,
                gpxPath: merged.gpxPath,
                hasGPX: cached.hasGPX && fileManager.fileExists(atPath: gpxURL(for: merged.id, userID: userID).path),
                hasParsedTrack: cached.hasParsedTrack && fileManager.fileExists(atPath: parsedTrackURL(for: merged.id, userID: userID).path),
                detailVersion: cached.detailVersion
            )
        }

        let archive = Archive(entries: entries)
        try persist(archive, for: userID)
        archives[userID] = archive
        return entries.map(\.ride).sorted { $0.date > $1.date }
    }

    func upsert(_ ride: Ride, gpxData: Data?, for userID: UUID) async throws {
        var archive = loadArchive(for: userID)
        let existingIndex = archive.entries.firstIndex { $0.ride.id == ride.id }
        let previous = existingIndex.map { archive.entries[$0] }
        let sameTrack = previous?.gpxPath == ride.gpxPath
        var entry = Entry(
            ride: ride,
            gpxPath: ride.gpxPath,
            hasGPX: sameTrack && (previous?.hasGPX ?? false),
            hasParsedTrack: sameTrack && (previous?.hasParsedTrack ?? false),
            detailVersion: sameTrack ? previous?.detailVersion : nil
        )

        if let gpxData {
            try write(gpxData, to: gpxURL(for: ride.id, userID: userID), userID: userID)
            try? fileManager.removeItem(at: parsedTrackURL(for: ride.id, userID: userID))
            try? removeDetailFiles(for: ride.id, userID: userID)
            entry.hasGPX = true
            entry.hasParsedTrack = false
            entry.detailVersion = nil
        }

        if let existingIndex {
            archive.entries[existingIndex] = entry
        } else {
            archive.entries.append(entry)
        }
        archive.entries.sort { $0.ride.date > $1.ride.date }
        try persist(archive, for: userID)
        archives[userID] = archive
    }

    func gpxData(for ride: Ride, userID: UUID) async -> Data? {
        let archive = loadArchive(for: userID)
        guard let entry = archive.entries.first(where: { $0.ride.id == ride.id }),
              entry.gpxPath == ride.gpxPath,
              entry.hasGPX else { return nil }
        return try? Data(contentsOf: gpxURL(for: ride.id, userID: userID), options: .mappedIfSafe)
    }

    func storeGPX(_ data: Data, for ride: Ride, userID: UUID) async throws {
        try await upsert(ride, gpxData: data, for: userID)
    }

    func parsedTrack(for ride: Ride, userID: UUID) async -> GPXTrack? {
        let archive = loadArchive(for: userID)
        guard let entry = archive.entries.first(where: { $0.ride.id == ride.id }),
              entry.gpxPath == ride.gpxPath,
              entry.hasParsedTrack,
              let data = try? Data(contentsOf: parsedTrackURL(for: ride.id, userID: userID), options: .mappedIfSafe),
              let parsed = try? PropertyListDecoder().decode(ParsedTrackArchive.self, from: data),
              parsed.version == 1,
              parsed.gpxPath == ride.gpxPath,
              parsed.points.count > 1 else { return nil }
        return GPXTrack(points: parsed.points)
    }

    func storeParsedTrack(_ track: GPXTrack, for ride: Ride, userID: UUID) async throws {
        var archive = loadArchive(for: userID)
        guard let index = archive.entries.firstIndex(where: { $0.ride.id == ride.id }),
              archive.entries[index].gpxPath == ride.gpxPath else { return }

        let payload = ParsedTrackArchive(gpxPath: ride.gpxPath, points: track.points)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try write(try encoder.encode(payload), to: parsedTrackURL(for: ride.id, userID: userID), userID: userID)
        archive.entries[index].hasParsedTrack = true
        try persist(archive, for: userID)
        archives[userID] = archive
    }

    func detail(for ride: Ride, userID: UUID, analysisVersion: Int) async -> RideDetail? {
        let archive = loadArchive(for: userID)
        guard let entry = archive.entries.first(where: { $0.ride.id == ride.id }),
              entry.gpxPath == ride.gpxPath,
              entry.detailVersion == analysisVersion,
              let data = try? Data(contentsOf: detailURL(for: ride.id, userID: userID, version: analysisVersion), options: .mappedIfSafe),
              let payload = try? PropertyListDecoder().decode(DetailArchive.self, from: data),
              payload.version == analysisVersion,
              payload.gpxPath == ride.gpxPath,
              payload.detail.id == ride.id else { return nil }
        return payload.detail
    }

    func storeDetail(
        _ detail: RideDetail,
        for ride: Ride,
        userID: UUID,
        analysisVersion: Int
    ) async throws {
        var archive = loadArchive(for: userID)
        guard let index = archive.entries.firstIndex(where: { $0.ride.id == ride.id }),
              archive.entries[index].gpxPath == ride.gpxPath else { return }

        let payload = DetailArchive(version: analysisVersion, gpxPath: ride.gpxPath, detail: detail)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try write(
            try encoder.encode(payload),
            to: detailURL(for: ride.id, userID: userID, version: analysisVersion),
            userID: userID
        )
        archive.entries[index].detailVersion = analysisVersion
        try persist(archive, for: userID)
        archives[userID] = archive
    }

    func journalEntries(for userID: UUID) async -> [JournalEntry] {
        if let cached = journalArchives[userID] { return cached }
        guard let data = try? Data(contentsOf: journalURL(for: userID)),
              let entries = try? Self.decoder.decode([JournalEntry].self, from: data) else {
            journalArchives[userID] = []
            return []
        }
        let sorted = Self.sortedJournal(entries)
        journalArchives[userID] = sorted
        return sorted
    }

    func replaceJournalEntries(_ entries: [JournalEntry], for userID: UUID) async throws {
        let sorted = Self.sortedJournal(entries)
        try write(try Self.encoder.encode(sorted), to: journalURL(for: userID), userID: userID)
        journalArchives[userID] = sorted
    }

    private func loadArchive(for userID: UUID) -> Archive {
        if let cached = archives[userID] { return cached }
        let url = indexURL(for: userID)
        guard let data = try? Data(contentsOf: url),
              let archive = try? Self.decoder.decode(Archive.self, from: data),
              archive.version == 1 else {
            let empty = Archive(entries: [])
            archives[userID] = empty
            return empty
        }
        archives[userID] = archive
        return archive
    }

    private func persist(_ archive: Archive, for userID: UUID) throws {
        try write(try Self.encoder.encode(archive), to: indexURL(for: userID), userID: userID)
    }

    private func write(_ data: Data, to url: URL, userID: UUID) throws {
        try prepareDirectory(for: userID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func prepareDirectory(for userID: UUID) throws {
        var directory = userDirectory(for: userID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    private func userDirectory(for userID: UUID) -> URL {
        rootURL.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }

    private func rideDirectory(for rideID: UUID, userID: UUID) -> URL {
        userDirectory(for: userID)
            .appendingPathComponent("rides", isDirectory: true)
            .appendingPathComponent(rideID.uuidString.lowercased(), isDirectory: true)
    }

    private func indexURL(for userID: UUID) -> URL {
        userDirectory(for: userID).appendingPathComponent("rides-v1.json")
    }

    private func journalURL(for userID: UUID) -> URL {
        userDirectory(for: userID).appendingPathComponent("journal-v1.json")
    }

    private func gpxURL(for rideID: UUID, userID: UUID) -> URL {
        rideDirectory(for: rideID, userID: userID).appendingPathComponent("track.gpx")
    }

    private func parsedTrackURL(for rideID: UUID, userID: UUID) -> URL {
        rideDirectory(for: rideID, userID: userID).appendingPathComponent("track-v1.plist")
    }

    private func detailURL(for rideID: UUID, userID: UUID, version: Int) -> URL {
        rideDirectory(for: rideID, userID: userID).appendingPathComponent("detail-v\(version).plist")
    }

    private func removeDetailFiles(for rideID: UUID, userID: UUID) throws {
        let directory = rideDirectory(for: rideID, userID: userID)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("detail-v") {
            try? fileManager.removeItem(at: file)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func sortedJournal(_ entries: [JournalEntry]) -> [JournalEntry] {
        entries.sorted { lhs, rhs in
            if lhs.rideDate != rhs.rideDate { return lhs.rideDate > rhs.rideDate }
            return lhs.index > rhs.index
        }
    }
}
