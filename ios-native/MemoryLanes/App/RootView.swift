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
    @ObservedObject var authStore: AuthStore
    @State private var ridePath = NavigationPath()
    @State private var routesPath = NavigationPath()
    @State private var journalPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    @State private var showingRecorder = false
    @State private var showingImporter = false
    @State private var refreshTrigger = UUID()

    private var rideService: RideServing {
        RideService(accessToken: { authStore.accessToken })
    }

    var body: some View {
        TabView {
            NavigationStack(path: $ridePath) {
                DashboardView(
                    viewModel: DashboardViewModel(rideService: rideService),
                    refreshTrigger: refreshTrigger,
                    onSelectRide: { ridePath.append($0) },
                    onStartRide: { showingRecorder = true },
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

            NavigationStack(path: $routesPath) {
                RoutesView(
                    viewModel: RoutesViewModel(
                        routeService: RouteService(accessToken: { authStore.accessToken })
                    ),
                    refreshTrigger: refreshTrigger,
                    onSelectRoute: { routesPath.append($0) }
                )
                .navigationDestination(for: PlannedRoute.self) { route in
                    PlannedRouteDetailView(route: route)
                }
            }
            .tabItem { Label("Routes", systemImage: "map") }

            NavigationStack(path: $journalPath) {
                JournalView(
                    viewModel: JournalViewModel(
                        journalService: JournalService(accessToken: { authStore.accessToken })
                    ),
                    refreshTrigger: refreshTrigger,
                    onSelectRide: { journalPath.append($0) }
                )
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(viewModel: RideDetailViewModel(ride: ride, rideService: rideService))
                }
            }
            .tabItem { Label("Journal", systemImage: "book") }

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
        }
        .fullScreenCover(isPresented: $showingRecorder) {
            if let session = authStore.session {
                RecordingView(session: session) { _ in
                    refreshTrigger = UUID()
                }
            }
        }
        .sheet(isPresented: $showingImporter) {
            if let session = authStore.session {
                GPXImportView(session: session) { _ in
                    refreshTrigger = UUID()
                }
            }
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
