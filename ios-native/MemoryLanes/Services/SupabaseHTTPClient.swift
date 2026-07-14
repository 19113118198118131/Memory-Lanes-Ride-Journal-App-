import Foundation

struct SupabaseHTTPClient {
    var baseURL: URL = SupabaseConfig.url
    var anonKey: String = SupabaseConfig.anonKey
    var session: URLSession = .shared

    func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseHTTPError.invalidURL }
        let request = request(url: url, method: "GET", accessToken: accessToken)
        return try await send(request)
    }

    func post<Body: Encodable, Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        accessToken: String? = nil,
        prefer: String? = nil
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseHTTPError.invalidURL }
        var request = request(url: url, method: "POST", accessToken: accessToken)
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = try JSONEncoder.supabase.encode(body)
        return try await send(request)
    }

    func patch<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        accessToken: String? = nil
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseHTTPError.invalidURL }
        var request = request(url: url, method: "PATCH", accessToken: accessToken)
        request.httpBody = try JSONEncoder.supabase.encode(body)
        try await sendWithoutDecoding(request)
    }

    func patch<Body: Encodable, Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        accessToken: String? = nil,
        prefer: String? = nil
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseHTTPError.invalidURL }
        var request = request(url: url, method: "PATCH", accessToken: accessToken)
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = try JSONEncoder.supabase.encode(body)
        return try await send(request)
    }

    func delete(
        path: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseHTTPError.invalidURL }
        let request = request(url: url, method: "DELETE", accessToken: accessToken)
        try await sendWithoutDecoding(request)
    }

    func upload(
        path: String,
        data: Data,
        contentType: String,
        accessToken: String
    ) async throws {
        let url = baseURL.appendingPathComponent(path)
        var request = request(url: url, method: "POST", accessToken: accessToken)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        try await sendWithoutDecoding(request)
    }

    func download(path: String, accessToken: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        let request = request(url: url, method: "GET", accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseHTTPError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder.supabase.decode(SupabaseErrorPayload.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseHTTPError.server(status: http.statusCode, message: message)
        }
        return data
    }

    private func request(url: URL, method: String, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseHTTPError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder.supabase.decode(SupabaseErrorPayload.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseHTTPError.server(status: http.statusCode, message: message)
        }
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    private func sendWithoutDecoding(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseHTTPError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder.supabase.decode(SupabaseErrorPayload.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseHTTPError.server(status: http.statusCode, message: message)
        }
    }
}

enum SupabaseHTTPError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Supabase URL is invalid."
        case .invalidResponse:
            return "Supabase returned an invalid response."
        case .server(_, let message):
            return message
        }
    }
}

private struct SupabaseErrorPayload: Decodable {
    let message: String?
}

extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        // Supabase timestamps carry fractional seconds, which `.iso8601` can't
        // parse. Route Date decoding through the shared, tolerant parser.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = SupabaseDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised Supabase date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
