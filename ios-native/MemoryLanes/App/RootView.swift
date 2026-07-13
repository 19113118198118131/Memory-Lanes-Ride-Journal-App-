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

    var body: some View {
        TabView {
            NavigationStack(path: $ridePath) {
                DashboardView(
                    viewModel: DashboardViewModel(rideService: rideService),
                    onSelectRide: { ridePath.append($0) }
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(viewModel: RideDetailViewModel(ride: ride, rideService: rideService))
                }
            }
            .tabItem { Label("Ride", systemImage: "location.north.line.fill") }

            NavigationStack {
                PlaceholderScreen(title: "Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
            }
            .tabItem { Label("Routes", systemImage: "map") }

            NavigationStack {
                PlaceholderScreen(title: "Journal", systemImage: "book.closed.fill")
            }
            .tabItem { Label("Journal", systemImage: "book") }

            NavigationStack {
                PlaceholderScreen(title: "Stats", systemImage: "chart.bar.fill")
            }
            .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}

// MARK: - PlaceholderScreen
//
// A designed empty state for tabs not yet rebuilt — never a blank page. Replaced
// screen-by-screen as Step 5 proceeds.

private struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        EmptyState(
            systemImage: systemImage,
            title: "\(title) — coming next",
            message: "This screen is being rebuilt on the new design system."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mlBackground)
        .navigationTitle(title)
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
