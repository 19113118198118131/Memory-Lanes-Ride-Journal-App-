import Foundation
import CoreLocation

struct GPXParser {
    func parse(data: Data) throws -> GPXTrack {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw GPXParserError.invalidXML(parser.parserError?.localizedDescription)
        }
        let track = GPXTrack(points: delegate.points)
        guard track.isValid else { throw GPXParserError.noTrackPoints }
        return track
    }
}

enum GPXParserError: LocalizedError {
    case invalidXML(String?)
    case noTrackPoints

    var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            return message ?? "That GPX file could not be read."
        case .noTrackPoints:
            return "That GPX file does not contain enough GPS track points."
        }
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var currentLatitude: Double?
    private var currentLongitude: Double?
    private var currentElevation: Double?
    private var currentTime: Date?
    private var currentElement = ""
    private var buffer = ""
    private var lastTrackTimestamp: Date?
    private var lastRouteTimestamp: Date?
    private let fallbackStartTime = Date()

    private var trackPoints: [RecordingPoint] = []
    private var routePoints: [RecordingPoint] = []

    var points: [RecordingPoint] {
        trackPoints.isEmpty ? routePoints : trackPoints
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""
        if elementName == "trkpt" || elementName == "rtept" {
            currentLatitude = Double(attributeDict["lat"] ?? "")
            currentLongitude = Double(attributeDict["lon"] ?? "")
            currentElevation = nil
            currentTime = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "ele" {
            currentElevation = Double(value)
        } else if elementName == "time" {
            currentTime = DateParsing.gpxDate(from: value)
        } else if elementName == "trkpt" {
            appendCurrentPoint(isTrack: true)
        } else if elementName == "rtept" {
            appendCurrentPoint(isTrack: false)
        }
        buffer = ""
    }

    private func appendCurrentPoint(isTrack: Bool) {
        guard let latitude = currentLatitude, let longitude = currentLongitude else { return }
        let previousTimestamp = isTrack ? lastTrackTimestamp : lastRouteTimestamp
        let timestamp = currentTime ?? previousTimestamp?.addingTimeInterval(1) ?? fallbackStartTime
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: currentElevation ?? 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            course: 0,
            speed: 0,
            timestamp: timestamp
        )
        if isTrack {
            trackPoints.append(RecordingPoint(location: location))
            lastTrackTimestamp = timestamp
        } else {
            routePoints.append(RecordingPoint(location: location))
            lastRouteTimestamp = timestamp
        }
    }
}

private enum DateParsing {
    static func gpxDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
