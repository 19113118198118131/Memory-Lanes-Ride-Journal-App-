import SwiftUI

// MARK: - RootView
//
// The tab shell. Mirrors the existing app's information architecture
// (Ride / Routes / Journal / Stats) with SF Symbols and the accent tint. Each
// tab owns its own navigation stack. Services are created here and injected into
// each screen's ViewModel so there are no globals.

struct RootView: View {
    @StateObject private var authStore = AuthStore()

    var body: some View {
        switch authStore.state {
        case .checking:
            ProgressView()
                .tint(.mlAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mlBackground)
        case .signedOut:
            AuthView(authStore: authStore)
        case .signedIn:
            MainTabShell(authStore: authStore)
        }
    }
}

private struct MainTabShell: View {
    private enum MainTab: Hashable {
        case ride
        case routes
        case journal
        case stats
    }

    @ObservedObject var authStore: AuthStore
    @State private var selectedTab: MainTab = .ride
    @State private var ridePath = NavigationPath()
    @State private var routesPath = NavigationPath()
    @State private var journalPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    @State private var showingRecorder = false
    @State private var showingImporter = false
    @State private var refreshTrigger = UUID()
    @State private var recorderRoute: PlannedRoute?
    @State private var toast: Toast?

    private var rideService: RideServing {
        RideService(accessToken: { await authStore.validAccessToken() })
    }

    private var routeService: RouteServing {
        RouteService(
            accessToken: { await authStore.validAccessToken() },
            userID: { authStore.session?.userID }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $ridePath) {
                DashboardView(
                    viewModel: DashboardViewModel(rideService: rideService),
                    refreshTrigger: refreshTrigger,
                    onSelectRide: { ridePath.append($0) },
                    onStartRide: {
                        recorderRoute = nil
                        showingRecorder = true
                    },
                    onImportRide: { showingImporter = true }
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(viewModel: RideDetailViewModel(ride: ride, rideService: rideService))
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            authStore.signOut()
                        } label: {
                            Image(systemName: "person.crop.circle.badge.xmark")
                        }
                        .accessibilityLabel("Sign out")
                    }
                }
            }
            .tabItem { Label("Ride", systemImage: "location.north.line.fill") }
            .tag(MainTab.ride)

            NavigationStack(path: $routesPath) {
                RoutesView(
                    viewModel: RoutesViewModel(
                        routeService: routeService
                    ),
                    refreshTrigger: refreshTrigger,
                    onSelectRoute: { routesPath.append($0) }
                )
                .navigationDestination(for: PlannedRoute.self) { route in
                    PlannedRouteDetailView(
                        route: route,
                        routeService: routeService,
                        onStartRide: { route in
                            recorderRoute = route
                            showingRecorder = true
                        },
                        onChanged: { refreshTrigger = UUID() },
                        onDeleted: {
                            refreshTrigger = UUID()
                            if !routesPath.isEmpty {
                                routesPath.removeLast()
                            }
                        }
                    )
                }
            }
            .tabItem { Label("Routes", systemImage: "map") }
            .tag(MainTab.routes)

            NavigationStack(path: $journalPath) {
                JournalView(
                    viewModel: JournalViewModel(
                        journalService: JournalService(accessToken: { await authStore.validAccessToken() })
                    ),
                    refreshTrigger: refreshTrigger,
                    onSelectRide: { journalPath.append($0) }
                )
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(viewModel: RideDetailViewModel(ride: ride, rideService: rideService))
                }
            }
            .tabItem { Label("Journal", systemImage: "book") }
            .tag(MainTab.journal)

            NavigationStack(path: $statsPath) {
                StatsView(
                    viewModel: StatsViewModel(rideService: rideService),
                    refreshTrigger: refreshTrigger,
                    onSelectRide: { statsPath.append($0) }
                )
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(viewModel: RideDetailViewModel(ride: ride, rideService: rideService))
                }
            }
            .tabItem { Label("Stats", systemImage: "chart.bar") }
            .tag(MainTab.stats)
        }
        .mlToast($toast)
        .fullScreenCover(isPresented: $showingRecorder) {
            if let session = authStore.session {
                RecordingView(
                    session: session,
                    plannedRoute: recorderRoute,
                    accessToken: { await authStore.validAccessToken() }
                ) { ride in
                    presentSavedRide(ride, message: "Ride saved to journal")
                }
            }
        }
        .sheet(isPresented: $showingImporter) {
            if let session = authStore.session {
                GPXImportView(
                    session: session,
                    accessToken: { await authStore.validAccessToken() }
                ) { ride in
                    presentSavedRide(ride, message: "GPX saved to journal")
                }
            }
        }
    }

    private func presentSavedRide(_ ride: Ride, message: String) {
        refreshTrigger = UUID()
        selectedTab = .ride
        ridePath = NavigationPath()
        routesPath = NavigationPath()
        journalPath = NavigationPath()
        statsPath = NavigationPath()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            ridePath.append(ride)
            toast = .success(message)
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
