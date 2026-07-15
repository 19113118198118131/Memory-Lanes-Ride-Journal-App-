import Foundation
import Observation

@MainActor
@Observable
final class RoutesViewModel {
    enum LoadState {
        case loading
        case loaded([PlannedRoute])
        case empty
        case failed(String)
    }

    enum GroupLoadState {
        case loading
        case loaded([GroupRideSummary])
        case empty
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var groupState: GroupLoadState = .loading
    private(set) var isSavingRoute = false
    private let routeService: RouteServing
    private let rideService: RideServing
    private let groupRideService: GroupRideServing?
    private let planner: IndependentRoutePlanner
    private var recommender = RideRecommendationEngine(ratedRides: [])

    init(
        routeService: RouteServing,
        rideService: RideServing,
        groupRideService: GroupRideServing? = nil,
        planner: IndependentRoutePlanner = IndependentRoutePlanner()
    ) {
        self.routeService = routeService
        self.rideService = rideService
        self.groupRideService = groupRideService
        self.planner = planner
    }

    var routes: [PlannedRoute] {
        if case .loaded(let routes) = state { return routes }
        return []
    }

    func load() async {
        state = .loading
        groupState = .loading
        await refreshAll()
        await refreshRecommendations()
    }

    func refreshAll() async {
        await refresh()
        await refreshGroupRides()
    }

    var recommendationStatus: String {
        recommender.isReady
            ? "Personalised from \(recommender.ratedCount) rated rides"
            : "Rate \(max(4 - recommender.ratedCount, 0)) more ride\(4 - recommender.ratedCount == 1 ? "" : "s") to unlock personal matches"
    }

    func recommendation(for vector: RouteMatchVector) -> RouteRecommendation? {
        recommender.score(vector)
    }

    func generateCandidates(for request: RoutePlanRequest) async throws -> [RouteCandidate] {
        try await planner.candidates(for: request)
            .map { candidate in
                var ranked = candidate
                ranked.recommendation = recommendation(for: candidate.matchVector)
                return ranked
            }
            .sorted { lhs, rhs in
                if lhs.matchTier != rhs.matchTier { return lhs.matchTier < rhs.matchTier }
                return lhs.rankingScore > rhs.rankingScore
            }
    }

    private func refreshRecommendations() async {
        do {
            recommender = RideRecommendationEngine(ratedRides: try await rideService.fetchRatedRideFeatures())
        } catch {
            // Personalisation is additive. Route planning remains fully usable
            // before the optional AI migration or when the rider is offline.
            recommender = RideRecommendationEngine(ratedRides: [])
        }
    }

    func refresh() async {
        do {
            let routes = try await routeService.fetchRoutes()
            state = routes.isEmpty ? .empty : .loaded(routes)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshGroupRides() async {
        guard let groupRideService else {
            groupState = .empty
            return
        }
        do {
            let groupRides = try await groupRideService.fetchMyGroupRides()
            groupState = groupRides.isEmpty ? .empty : .loaded(groupRides)
        } catch is CancellationError {
        } catch {
            groupState = .failed(error.localizedDescription)
        }
    }

    func createRoute(_ draft: PlannedRouteDraft) async throws -> PlannedRoute {
        isSavingRoute = true
        defer { isSavingRoute = false }

        let route = try await routeService.createRoute(draft)
        var updatedRoutes = routes
        updatedRoutes.insert(route, at: 0)
        state = .loaded(updatedRoutes)
        return route
    }
}
