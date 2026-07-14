import Foundation

actor AccountDataExportService {
    private let client: SupabaseHTTPClient
    private let maximumConcurrentDownloads = 4

    init(client: SupabaseHTTPClient = SupabaseHTTPClient()) {
        self.client = client
    }

    func makeExport(
        userID: UUID,
        email: String?,
        accessToken: String
    ) async throws -> URL {
        async let rideLogs: JSONValue = client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "ride_date.desc")
            ],
            accessToken: accessToken
        )
        async let plannedRoutes: JSONValue = client.get(
            path: "rest/v1/planned_routes",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )

        let (rides, routes) = try await (rideLogs, plannedRoutes)
        let gpxFiles = await downloadGPXFiles(paths: rides.gpxStoragePaths, accessToken: accessToken)
        let package = AccountDataExport(
            exportedAt: Date(),
            account: .init(userID: userID, email: email),
            rideLogs: rides,
            plannedRoutes: routes,
            gpxFiles: gpxFiles
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(package)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.fileName(for: package.exportedAt))
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func downloadGPXFiles(paths: [String], accessToken: String) async -> [GPXFileExport] {
        guard !paths.isEmpty else { return [] }
        var iterator = paths.makeIterator()
        var results: [GPXFileExport] = []

        await withTaskGroup(of: GPXFileExport.self) { group in
            for _ in 0..<min(maximumConcurrentDownloads, paths.count) {
                guard let path = iterator.next() else { break }
                group.addTask { [client] in
                    await Self.downloadGPX(path: path, accessToken: accessToken, client: client)
                }
            }

            for await result in group {
                results.append(result)
                if let path = iterator.next() {
                    group.addTask { [client] in
                        await Self.downloadGPX(path: path, accessToken: accessToken, client: client)
                    }
                }
            }
        }

        return results.sorted { $0.storagePath < $1.storagePath }
    }

    private static func downloadGPX(
        path: String,
        accessToken: String,
        client: SupabaseHTTPClient
    ) async -> GPXFileExport {
        do {
            let data = try await client.download(
                path: "storage/v1/object/gpx-files/\(path)",
                accessToken: accessToken
            )
            if let xml = String(data: data, encoding: .utf8) {
                return GPXFileExport(storagePath: path, xml: xml, base64: nil, error: nil)
            }
            return GPXFileExport(storagePath: path, xml: nil, base64: data.base64EncodedString(), error: nil)
        } catch {
            return GPXFileExport(
                storagePath: path,
                xml: nil,
                base64: nil,
                error: error.localizedDescription
            )
        }
    }

    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "memory-lanes-export-\(formatter.string(from: date)).json"
    }
}

struct AccountDataExport: Encodable, Sendable {
    let formatVersion = 1
    let exportedAt: Date
    let account: AccountExportIdentity
    let rideLogs: JSONValue
    let plannedRoutes: JSONValue
    let gpxFiles: [GPXFileExport]
}

struct AccountExportIdentity: Encodable, Sendable {
    let userID: UUID
    let email: String?
}

struct GPXFileExport: Encodable, Sendable {
    let storagePath: String
    let xml: String?
    let base64: String?
    let error: String?
}

enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var gpxStoragePaths: [String] {
        guard case .array(let rows) = self else { return [] }
        return Array(Set(rows.compactMap { row in
            guard case .object(let fields) = row,
                  case .string(let path)? = fields["gpx_path"],
                  !path.isEmpty else { return nil }
            return path
        })).sorted()
    }
}
