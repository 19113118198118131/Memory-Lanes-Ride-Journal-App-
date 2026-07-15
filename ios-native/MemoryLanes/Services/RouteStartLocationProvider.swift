import Foundation
import CoreLocation
import MapKit

struct RouteStartSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

struct RouteStartPlace: Codable, Identifiable, Equatable {
    let title: String
    let subtitle: String
    let coordinate: Coordinate

    var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
}

@MainActor
final class RouteStartLocationProvider: NSObject, ObservableObject {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var isLocating = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedPlace: RouteStartPlace?
    @Published private(set) var suggestions: [RouteStartSuggestion] = []
    @Published private(set) var recentPlaces: [RouteStartPlace] = []
    @Published var query = "" {
        didSet { updateSearch(for: query) }
    }

    private let manager = CLLocationManager()
    private let completer = MKLocalSearchCompleter()
    private var completions: [String: MKLocalSearchCompletion] = [:]
    private var searchTask: Task<Void, Never>?
    private var searchRegionCenter: Coordinate?
    private var shouldRequestLocationAfterPermission = false
    private var isUpdatingQueryInternally = false
    private static let recentPlacesKey = "route-planner-recent-starts"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        loadRecentPlaces()
    }

    var summary: String {
        if let coordinate {
            if let subtitle = selectedPlace?.subtitle, !subtitle.isEmpty { return subtitle }
            return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
        return "Use current location to find nearby roads"
    }

    func useCurrentLocation() {
        errorMessage = nil
        isLocating = true

        switch manager.authorizationStatus {
        case .notDetermined:
            shouldRequestLocationAfterPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Allow location access in Settings to plan from your current position."
        @unknown default:
            isLocating = false
            errorMessage = "Current location is not available on this device."
        }
    }

    func selectSuggestion(_ suggestion: RouteStartSuggestion) {
        guard let completion = completions[suggestion.id] else { return }
        searchTask?.cancel()
        isSearching = true
        errorMessage = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
                guard !Task.isCancelled, let item = response.mapItems.first else { return }
                let coordinate = item.placemark.coordinate
                let place = RouteStartPlace(
                    title: item.name ?? suggestion.title,
                    subtitle: suggestion.subtitle,
                    coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                )
                apply(place)
            } catch is CancellationError {
            } catch {
                isSearching = false
                errorMessage = "That start location could not be resolved. Try a nearby road or suburb."
            }
        }
    }

    func selectRecentPlace(_ place: RouteStartPlace) {
        apply(place)
    }

    func clearSearch() {
        searchTask?.cancel()
        isSearching = false
        isUpdatingQueryInternally = true
        query = ""
        isUpdatingQueryInternally = false
        coordinate = nil
        selectedPlace = nil
        suggestions = []
        completions = [:]
    }

    private func updateSearch(for query: String) {
        guard !isUpdatingQueryInternally else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchOrigin = searchRegionCenter
        if trimmed != selectedPlace?.title {
            coordinate = nil
            selectedPlace = nil
        }
        guard trimmed.count >= 2 else {
            suggestions = []
            completions = [:]
            return
        }
        if let searchOrigin {
            completer.region = MKCoordinateRegion(
                center: searchOrigin.clCoordinate,
                latitudinalMeters: 150_000,
                longitudinalMeters: 150_000
            )
        }
        completer.queryFragment = trimmed
    }

    private func apply(_ place: RouteStartPlace) {
        coordinate = place.coordinate
        searchRegionCenter = place.coordinate
        selectedPlace = place
        isLocating = false
        isSearching = false
        errorMessage = nil
        suggestions = []
        completions = [:]
        isUpdatingQueryInternally = true
        query = place.title
        isUpdatingQueryInternally = false
        recentPlaces.removeAll { $0.id == place.id }
        recentPlaces.insert(place, at: 0)
        recentPlaces = Array(recentPlaces.prefix(3))
        if let data = try? JSONEncoder().encode(recentPlaces) {
            UserDefaults.standard.set(data, forKey: Self.recentPlacesKey)
        }
    }

    private func loadRecentPlaces() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentPlacesKey),
              let places = try? JSONDecoder().decode([RouteStartPlace].self, from: data) else { return }
        recentPlaces = places
    }
}

extension RouteStartLocationProvider: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shouldRequestLocationAfterPermission else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            shouldRequestLocationAfterPermission = false
            manager.requestLocation()
        case .denied, .restricted:
            shouldRequestLocationAfterPermission = false
            isLocating = false
            errorMessage = "Allow location access in Settings to plan from your current position."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let updatedCoordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        coordinate = updatedCoordinate
        searchRegionCenter = updatedCoordinate
        selectedPlace = RouteStartPlace(
            title: "Current location",
            subtitle: String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude),
            coordinate: updatedCoordinate
        )
        isUpdatingQueryInternally = true
        query = "Current location"
        isUpdatingQueryInternally = false
        isLocating = false
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        errorMessage = "Could not find your current location."
    }
}

extension RouteStartLocationProvider: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(5))
        completions = Dictionary(uniqueKeysWithValues: results.enumerated().map { index, completion in
            let id = "\(index)|\(completion.title)|\(completion.subtitle)"
            return (id, completion)
        })
        suggestions = results.enumerated().map { index, completion in
            RouteStartSuggestion(
                id: "\(index)|\(completion.title)|\(completion.subtitle)",
                title: completion.title,
                subtitle: completion.subtitle
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
