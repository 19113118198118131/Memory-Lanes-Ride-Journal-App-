import Foundation
import Testing
@testable import MemoryLanes

@MainActor
struct StatsViewModelTests {
    @Test func biggestClimbUsesOneRideInsteadOfAddingEveryRide() async {
        let smaller = Ride(
            title: "Smaller climb",
            date: Date(),
            distanceMeters: 20_000,
            durationSeconds: 1_800,
            elevationGainMeters: 420
        )
        let biggest = Ride(
            title: "Biggest climb",
            date: Date().addingTimeInterval(-3_600),
            distanceMeters: 30_000,
            durationSeconds: 2_400,
            elevationGainMeters: 1_180
        )
        let viewModel = StatsViewModel(
            rideService: PreviewRideService(delay: .milliseconds(0), rides: [smaller, biggest])
        )

        await viewModel.load()

        #expect(viewModel.highestRide?.id == biggest.id)
        #expect(viewModel.highestRide?.elevationGainMeters == 1_180)
    }
}
