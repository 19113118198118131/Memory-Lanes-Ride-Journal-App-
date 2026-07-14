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

    private(set) var state: LoadState = .loading
    private let routeService: RouteServing

    init(routeService: RouteServing) {
        self.routeService = routeService
    }

    var routes: [PlannedRoute] {
        if case .loaded(let routes) = state { return routes }
        return []
    }

    func load() async {
        state = .loading
        await refresh()
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
}
