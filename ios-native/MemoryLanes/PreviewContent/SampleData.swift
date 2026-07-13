import Foundation

// MARK: - Sample data
//
// Used exclusively by `#Preview` blocks so every component can be shown in its
// populated state without a backend. Never referenced from production code.

enum SampleData {
    /// A short, hand-authored ridge road so map thumbnails have a real shape.
    static let ridgeRoute: [Coordinate] = [
        .init(latitude: 36.998, longitude: -121.520),
        .init(latitude: 37.004, longitude: -121.512),
        .init(latitude: 37.010, longitude: -121.515),
        .init(latitude: 37.016, longitude: -121.508),
        .init(latitude: 37.022, longitude: -121.511),
        .init(latitude: 37.030, longitude: -121.503),
        .init(latitude: 37.035, longitude: -121.494),
        .init(latitude: 37.041, longitude: -121.498),
        .init(latitude: 37.048, longitude: -121.489)
    ]

    static let hero = Ride(
        title: "Skyline Ridge Loop",
        date: Date().addingTimeInterval(-3600 * 6),
        distanceMeters: 84_300,
        durationSeconds: 7_920,
        elevationGainMeters: 1_240,
        flowScore: 87,
        locationName: "Santa Cruz Mountains",
        source: .live,
        routePreview: ridgeRoute
    )

    static let rides: [Ride] = [
        hero,
        Ride(
            title: "Coast Road Morning",
            date: Date().addingTimeInterval(-86_400 * 2),
            distanceMeters: 52_100,
            durationSeconds: 5_400,
            elevationGainMeters: 610,
            flowScore: 79,
            locationName: "Highway 1",
            source: .strava,
            routePreview: ridgeRoute
        ),
        Ride(
            title: "Backroads Blast",
            date: Date().addingTimeInterval(-86_400 * 5),
            distanceMeters: 121_800,
            durationSeconds: 11_700,
            elevationGainMeters: 2_030,
            flowScore: 92,
            locationName: "Alpine County",
            source: .gpx,
            routePreview: ridgeRoute
        )
    ]

    /// A synthetic elevation profile (metres) for chart previews.
    static let elevationSamples: [ElevationSample] = (0..<120).map { i in
        let d = Double(i) / 120
        let base = 300 + 900 * sin(d * .pi)
        let noise = 40 * sin(d * .pi * 9)
        return ElevationSample(distanceKm: d * 84.3, elevationM: base + noise)
    }
}

/// One point on an elevation chart.
struct ElevationSample: Identifiable, Hashable, Sendable {
    var id: Double { distanceKm }
    let distanceKm: Double
    let elevationM: Double
}
