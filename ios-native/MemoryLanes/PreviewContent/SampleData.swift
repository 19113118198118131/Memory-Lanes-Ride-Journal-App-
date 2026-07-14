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

    static let plannedRoutes: [PlannedRoute] = [
        .init(
            id: UUID(),
            title: "Ridge Coffee Loop",
            distanceKm: 72.4,
            elevationM: 890,
            waypoints: [ridgeRoute[0], ridgeRoute[3], ridgeRoute[6], ridgeRoute[0]],
            route: ridgeRoute,
            createdAt: Date().addingTimeInterval(-86_400),
            isPublic: false,
            shareToken: nil
        ),
        .init(
            id: UUID(),
            title: "Coast Range Sweepers",
            distanceKm: 118.0,
            elevationM: 1420,
            waypoints: [ridgeRoute[0], ridgeRoute[2], ridgeRoute[8]],
            route: ridgeRoute.reversed(),
            createdAt: Date().addingTimeInterval(-86_400 * 5),
            isPublic: true,
            shareToken: UUID()
        )
    ]

    /// A synthetic elevation profile (metres) for chart previews.
    static let elevationSamples: [ElevationSample] = (0..<120).map { i in
        let d = Double(i) / 120
        let base = 300 + 900 * sin(d * .pi)
        let noise = 40 * sin(d * .pi * 9)
        return ElevationSample(distanceKm: d * 84.3, elevationM: base + noise)
    }

    static let replayPoints: [ReplayPoint] = elevationSamples.enumerated().map { index, sample in
        let routeIndex = min(index * ridgeRoute.count / max(elevationSamples.count, 1), ridgeRoute.count - 1)
        return ReplayPoint(
            index: index,
            coordinate: ridgeRoute[routeIndex],
            elapsedSeconds: Double(index) * 66,
            distanceKm: sample.distanceKm,
            elevationMeters: sample.elevationM,
            speedKmh: 58 + 18 * sin(Double(index) / 12)
        )
    }

    static let corners: [CornerTicket] = [
        .init(index: 1, shape: .rightHairpin, entrySpeed: 74, apexSpeed: 38, exitSpeed: 61,
              verdict: .smooth, tip: "Great patience on entry — trail-braked right to the apex.",
              repeatNote: "Ridden 4× · apex today 38 km/h, a new best"),
        .init(index: 2, shape: .leftSweeper, entrySpeed: 88, apexSpeed: 71, exitSpeed: 95,
              verdict: .tidy, tip: "Carried strong corner speed and got on the gas early."),
        .init(index: 3, shape: .rightSweeper, entrySpeed: 92, apexSpeed: 58, exitSpeed: 70,
              verdict: .rushed, tip: "A touch quick on the brakes — try releasing 10 m sooner."),
        .init(index: 4, shape: .leftHairpin, entrySpeed: 66, apexSpeed: 34, exitSpeed: 58,
              verdict: .early, tip: "Apex arrived early; look further through the exit next time.")
    ]

    static let moments: [Moment] = [
        .init(note: "Fog lifting over the ridge — unreal light.",
              coordinate: ridgeRoute[2], symbol: "camera.fill"),
        .init(note: "Coffee stop at the summit café.",
              coordinate: ridgeRoute[5], symbol: "cup.and.saucer.fill"),
        .init(note: "New personal best through the esses.",
              coordinate: ridgeRoute[7], symbol: "flag.checkered")
    ]

    static let journalEntries: [JournalEntry] = [
        .init(
            id: "sample-0",
            title: "Ridge light",
            note: "Fog lifting over the ridge — unreal light.",
            ride: hero,
            rideDate: hero.date,
            index: 0,
            coordinate: ridgeRoute[2],
            speedKmh: 62,
            elevationMeters: 690
        ),
        .init(
            id: "sample-1",
            title: "Summit stop",
            note: "Coffee stop at the summit cafe.",
            ride: rides[1],
            rideDate: rides[1].date,
            index: 1,
            coordinate: ridgeRoute[5],
            speedKmh: 0,
            elevationMeters: 920
        ),
        .init(
            id: "sample-2",
            title: "The esses",
            note: "New personal best through the esses.",
            ride: rides[2],
            rideDate: rides[2].date,
            index: 2,
            coordinate: ridgeRoute[7],
            speedKmh: 74,
            elevationMeters: 740
        )
    ]

    static let weather = Weather(
        temperatureC: 18, condition: "Partly cloudy", windKph: 12, symbol: "cloud.sun.fill"
    )

    static let heroDetail = RideDetail(
        id: hero.id,
        routePreview: ridgeRoute,
        replayPoints: replayPoints,
        elevation: elevationSamples,
        corners: corners,
        moments: moments,
        weather: weather,
        coachScore: 87,
        debrief: "Your smoothest ride this month. Corner exits were consistently strong — the one thing to practise next time is releasing the brakes a touch earlier into fast right-handers."
    )
}
