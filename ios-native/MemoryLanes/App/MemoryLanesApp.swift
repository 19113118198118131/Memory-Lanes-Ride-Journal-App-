import SwiftUI

// MARK: - App entry point
//
// The app is dark-first (Tesla-style true-dark identity), so we force the dark
// appearance rather than following the system — every surface is designed on
// `#0A0A0A`. Dependencies are constructed once here and injected downward.

@main
struct MemoryLanesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.mlAccent)
        }
    }
}
