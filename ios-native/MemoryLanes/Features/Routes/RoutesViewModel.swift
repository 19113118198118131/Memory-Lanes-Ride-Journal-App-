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

    enum CommunityLoadState {
        case loading
        case loaded([CommunityGroupRideSummary])
        case empty
        case failed(String)
    }

    enum CandidateLoadState {
        case idle
        case loading
        case loaded([RouteCandidate])
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var groupState: GroupLoadState = .loading
    private(set) var communityState: CommunityLoadState = .loading
    private(set) var candidateState: CandidateLoadState = .idle
    private(set) var isSavingRoute = false
    private let routeService: RouteServing
    private let rideService: RideServing
    private let groupRideService: GroupRideServing?
    private let planner: IndependentRoutePlanner
    private let elevationService: any RouteElevationProviding
    private var recommender = RideRecommendationEngine(ratedRides: [])
    private var candidateTask: Task<[RouteCandidate], Error>?
    private var candidateGeneration = 0

    init(
        routeService: RouteServing,
        rideService: RideServing,
        groupRideService: GroupRideServing? = nil,
        planner: IndependentRoutePlanner = IndependentRoutePlanner(),
        elevationService: any RouteElevationProviding = OpenMeteoElevationService()
    ) {
        self.routeService = routeService
        self.rideService = rideService
        self.groupRideService = groupRideService
        self.planner = planner
        self.elevationService = elevationService
    }

    var routes: [PlannedRoute] {
        if case .loaded(let routes) = state { return routes }
        return []
    }

    func load() async {
        state = .loading
        groupState = .loading
        communityState = .loading
        await refreshAll()
        await refreshRecommendations()
    }

    func refreshAll() async {
        await refresh()
        await refreshGroupRides()
        await refreshCommunityRides()
    }

    var recommendationStatus: String {
        recommender.isReady
            ? "Personalised from \(recommender.ratedCount) rated rides"
            : "Rate \(max(4 - recommender.ratedCount, 0)) more ride\(4 - recommender.ratedCount == 1 ? "" : "s") to unlock personal matches"
    }

    func recommendation(for vector: RouteMatchVector) -> RouteRecommendation? {
        recommender.score(vector)
    }

    var isGeneratingCandidates: Bool {
        if case .loading = candidateState { return true }
        return false
    }

    func generateCandidates(for request: RoutePlanRequest) async {
        candidateTask?.cancel()
        candidateGeneration += 1
        let generation = candidateGeneration
        candidateState = .loading

        let planner = planner
        let task = Task { try await planner.candidates(for: request) }
        candidateTask = task

        do {
            let generated = try await task.value
            guard generation == candidateGeneration else { return }
            // Fill in elevation (MapKit doesn't provide it) before ranking, so
            // both the displayed Ascent stat and the personalised match use it.
            let enriched = await enrichElevation(generated)
            guard generation == candidateGeneration else { return }
            let ranked = enriched.map { candidate in
                var ranked = candidate
                ranked.recommendation = recommendation(for: candidate.matchVector)
                return ranked
            }
            .sorted { lhs, rhs in
                if lhs.matchTier != rhs.matchTier { return lhs.matchTier < rhs.matchTier }
                return lhs.rankingScore > rhs.rankingScore
            }
            candidateState = ranked.isEmpty
                ? .failed(IndependentRoutePlanningError.noRoutes.localizedDescription)
                : .loaded(ranked)
        } catch is CancellationError {
            guard generation == candidateGeneration else { return }
            candidateState = .idle
        } catch {
            guard generation == candidateGeneration else { return }
            candidateState = .failed(error.localizedDescription)
        }

        if generation == candidateGeneration {
            candidateTask = nil
        }
    }

    // Best-effort, concurrent elevation lookup for the returned candidates. Any
    // candidate whose lookup fails keeps its nil elevation (shown as "--"), so a
    // flaky or offline elevation service never blocks route planning.
    private func enrichElevation(_ candidates: [RouteCandidate]) async -> [RouteCandidate] {
        guard !candidates.isEmpty else { return candidates }
        return await withTaskGroup(of: (Int, Double?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                let preview = candidate.preview
                group.addTask { [elevationService] in
                    (index, try? await elevationService.elevationGainMeters(along: preview))
                }
            }
            var result = candidates
            for await (index, gain) in group {
                if let gain { result[index].elevationM = gain }
            }
            return result
        }
    }

    func clearCandidateSession() {
        candidateGeneration += 1
        candidateTask?.cancel()
        candidateTask = nil
        candidateState = .idle
    }

    func cancelCandidateGeneration() {
        guard isGeneratingCandidates else { return }
        clearCandidateSession()
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

    func refreshCommunityRides() async {
        guard let groupRideService else {
            communityState = .empty
            return
        }
        do {
            let groupRides = try await groupRideService.fetchCommunityGroupRides()
            communityState = groupRides.isEmpty ? .empty : .loaded(groupRides)
        } catch is CancellationError {
        } catch {
            communityState = .failed(error.localizedDescription)
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
