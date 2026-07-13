import Foundation

// MARK: - RideServing
//
// The services layer is protocol-first so screens depend on an abstraction,
// not a concrete backend. `RideService` will wrap Supabase; `PreviewRideService`
// feeds sample data to previews and tests. Both are injected, never global.

protocol RideServing: Sendable {
    func fetchRides() async throws -> [Ride]
}

// MARK: - Preview / demo implementation

/// Returns bundled sample rides after a short delay so skeleton loaders are
/// actually visible in previews and the simulator. Stores only `Sendable`
/// values (no `any Error` existential) so it passes complete concurrency checks.
struct PreviewRideService: RideServing {
    var delay: Duration = .milliseconds(600)
    var rides: [Ride] = SampleData.rides
    var failure: RideServiceError? = nil

    func fetchRides() async throws -> [Ride] {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return rides
    }
}

// MARK: - Live implementation (skeleton)
//
// The real client will read from Supabase (`ride_logs`) and map rows into the
// `Ride` domain model. Left as a typed stub here so the dependency graph and
// injection points are in place before the network work lands.

struct RideService: RideServing {
    // let client: SupabaseClient  // wired in a later step

    func fetchRides() async throws -> [Ride] {
        // TODO: fetch `ride_logs` for the signed-in user, decode GPX previews,
        // and map to `[Ride]`. Runs off the main actor via async/await.
        throw RideServiceError.notImplemented
    }
}

enum RideServiceError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notImplemented: "Ride syncing isn’t connected yet."
        }
    }
}
