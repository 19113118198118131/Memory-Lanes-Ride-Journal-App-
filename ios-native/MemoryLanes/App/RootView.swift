import SwiftUI

// MARK: - RootView
//
// The tab shell. Mirrors the existing app's information architecture
// (Ride / Routes / Journal / Stats) with SF Symbols and the accent tint. Each
// tab owns its own navigation stack. Services are created here and injected into
// each screen's ViewModel so there are no globals.

struct RootView: View {
    // Swap `PreviewRideService` for the live `RideService` once Supabase is wired.
    private let rideService: RideServing = PreviewRideService()
    @State private var ridePath = NavigationPath()
    @State private var showingRecorder = false

    var body: some View {
        TabView {
            NavigationStack(path: $ridePath) {
                DashboardView(
                    viewModel: DashboardViewModel(rideService: rideService),
                    onSelectRide: { ridePath.append($0) },
                    onStartRide: { showingRecorder = true }
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(viewModel: RideDetailViewModel(ride: ride, rideService: rideService))
                }
            }
            .tabItem { Label("Ride", systemImage: "location.north.line.fill") }

            NavigationStack {
                RoutesView()
            }
            .tabItem { Label("Routes", systemImage: "map") }

            NavigationStack {
                JournalView()
            }
            .tabItem { Label("Journal", systemImage: "book") }

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
        .fullScreenCover(isPresented: $showingRecorder) {
            RecordingView()
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
