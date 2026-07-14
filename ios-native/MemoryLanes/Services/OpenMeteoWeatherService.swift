import Foundation

struct OpenMeteoWeatherService {
    var session: URLSession = .shared

    func fetchWeather(at coordinate: Coordinate, rideDate: Date) async throws -> Weather {
        let dateString = Self.dayFormatter.string(from: rideDate)
        let ageDays = Date().timeIntervalSince(rideDate) / 86_400
        let host = ageDays > 5.5 ? "archive-api.open-meteo.com" : "api.open-meteo.com"

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = ageDays > 5.5 ? "/v1/archive" : "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "start_date", value: dateString),
            URLQueryItem(name: "end_date", value: dateString),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        guard let url = components.url else { throw WeatherServiceError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.requestFailed
        }

        let decoded = try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: data)
        let targetHour = Self.hourFormatter.string(from: rideDate)
        let index = decoded.hourly.time.firstIndex { $0.prefix(targetHour.count) == targetHour } ?? 0
        guard let temperature = decoded.hourly.temperature[safe: index] else {
            throw WeatherServiceError.noWeather
        }

        let code = decoded.hourly.weatherCode[safe: index] ?? 2
        let condition = WeatherCondition(code: code)
        return Weather(
            temperatureC: temperature,
            condition: condition.title,
            windKph: decoded.hourly.windSpeed[safe: index] ?? 0,
            symbol: condition.symbol,
            precipitationMm: decoded.hourly.precipitation[safe: index]
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH"
        return formatter
    }()
}

enum WeatherServiceError: LocalizedError {
    case invalidURL
    case requestFailed
    case noWeather

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The weather request could not be built."
        case .requestFailed: "The weather service did not respond."
        case .noWeather: "No weather was available for this ride."
        }
    }
}

private struct OpenMeteoWeatherResponse: Decodable {
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let precipitation: [Double]
        let weatherCode: [Int]
        let windSpeed: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case precipitation
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }
}

private struct WeatherCondition {
    let title: String
    let symbol: String

    init(code: Int) {
        switch code {
        case 0:
            title = "Clear"
            symbol = "sun.max.fill"
        case 1:
            title = "Mostly clear"
            symbol = "sun.max.fill"
        case 2:
            title = "Partly cloudy"
            symbol = "cloud.sun.fill"
        case 3:
            title = "Overcast"
            symbol = "cloud.fill"
        case 45, 48:
            title = "Fog"
            symbol = "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            title = "Drizzle"
            symbol = "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            title = "Rain"
            symbol = "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            title = "Snow"
            symbol = "cloud.snow.fill"
        case 95, 96, 99:
            title = "Thunderstorm"
            symbol = "cloud.bolt.rain.fill"
        default:
            title = "Mixed conditions"
            symbol = "cloud.sun.fill"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
