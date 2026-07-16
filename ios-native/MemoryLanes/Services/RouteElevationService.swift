import Foundation

// MARK: - Route elevation
//
// The route planner scores geometry from MapKit, which does not return
// elevation. Rather than leave the "Ascent" stat blank, we sample the route
// polyline against Open-Meteo's free elevation API (no key, same source the web
// app uses) and sum the positive climbs. Enrichment is always best-effort: if
// the lookup fails the candidate simply keeps a nil elevation and the UI shows
// "--", exactly as before.

protocol RouteElevationProviding: Sendable {
    func elevationGainMeters(along coordinates: [Coordinate]) async throws -> Double
}

struct OpenMeteoElevationService: RouteElevationProviding {
    var session: URLSession = .shared

    // Open-Meteo accepts up to 100 coordinates in one elevation request.
    private static let maxSamples = 100

    func elevationGainMeters(along coordinates: [Coordinate]) async throws -> Double {
        let samples = coordinates.decimated(maxCount: Self.maxSamples)
        guard samples.count >= 2 else { return 0 }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/elevation"
        components.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: samples.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")
            ),
            URLQueryItem(
                name: "longitude",
                value: samples.map { String(format: "%.5f", $0.longitude) }.joined(separator: ",")
            )
        ]
        guard let url = components.url else { throw RouteElevationError.invalidURL }

        // Elevation is a nice-to-have stat, so cap the wait: a slow lookup must
        // never hold up showing route candidates.
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RouteElevationError.requestFailed
        }

        let decoded = try JSONDecoder().decode(OpenMeteoElevationResponse.self, from: data)
        return Self.positiveGain(decoded.elevation)
    }

    // Sum of upward steps only — the same "elevation gain" convention the rest of
    // the app uses. Exposed for unit testing without touching the network.
    static func positiveGain(_ elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        return zip(elevations, elevations.dropFirst()).reduce(0) { total, pair in
            let delta = pair.1 - pair.0
            return delta > 0 ? total + delta : total
        }
    }
}

enum RouteElevationError: LocalizedError {
    case invalidURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The elevation request could not be built."
        case .requestFailed: "The elevation service did not respond."
        }
    }
}

private struct OpenMeteoElevationResponse: Decodable {
    let elevation: [Double]
}
