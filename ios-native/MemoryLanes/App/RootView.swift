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
    @State private var showingAccount = false
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

    private var groupRideService: GroupRideServing {
        GroupRideService(
            accessToken: { await authStore.validAccessToken() },
            userID: authStore.session?.userID
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
                    onImportRide: { showingImporter = true },
                    onShowStats: { selectedTab = .stats }
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(
                        viewModel: RideDetailViewModel(ride: ride, rideService: rideService),
                        onRideChanged: { _ in refreshTrigger = UUID() }
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAccount = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .accessibilityLabel("Account")
                    }
                }
            }
            .tabItem { Label("Ride", systemImage: "location.north.line.fill") }
            .tag(MainTab.ride)

            NavigationStack(path: $routesPath) {
                RoutesView(
                    viewModel: RoutesViewModel(
                        routeService: routeService,
                        rideService: rideService,
                        groupRideService: groupRideService
                    ),
                    refreshTrigger: refreshTrigger,
                    onSelectRoute: { routesPath.append($0) },
                    onSelectGroupRide: { routesPath.append($0) }
                )
                .navigationDestination(for: PlannedRoute.self) { route in
                    PlannedRouteDetailView(
                        route: route,
                        routeService: routeService,
                        groupRideService: groupRideService,
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
                .navigationDestination(for: GroupRideSummary.self) { groupRide in
                    GroupRideLobbyView(
                        viewModel: GroupRideViewModel(
                            shareToken: groupRide.shareToken,
                            service: groupRideService
                        ),
                        onStartRoute: { route in
                            recorderRoute = route
                            showingRecorder = true
                        },
                        onEnded: {
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
                    RideDetailView(
                        viewModel: RideDetailViewModel(ride: ride, rideService: rideService),
                        onRideChanged: { _ in refreshTrigger = UUID() }
                    )
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
                    RideDetailView(
                        viewModel: RideDetailViewModel(ride: ride, rideService: rideService),
                        onRideChanged: { _ in refreshTrigger = UUID() }
                    )
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
        .sheet(isPresented: $showingAccount) {
            if let session = authStore.session {
                AccountView(
                    email: session.email,
                    userID: session.userID,
                    accessToken: { await authStore.validAccessToken() },
                    onSignOut: { authStore.signOut() }
                )
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
