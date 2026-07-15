import XCTest
@testable import MemoryLanes

@MainActor
final class RideRenameTests: XCTestCase {
    func testRenameTrimsTitleAndUpdatesRide() async {
        let ride = SampleData.rides[0]
        let viewModel = RideDetailViewModel(
            ride: ride,
            rideService: PreviewRideService(delay: .zero, rides: [ride])
        )

        let renamed = await viewModel.renameRide(to: "  Coromandel Loop  ")

        XCTAssertTrue(renamed)
        XCTAssertEqual(viewModel.ride.title, "Coromandel Loop")
        XCTAssertNil(viewModel.renameErrorMessage)
    }

    func testRenameRejectsEmptyTitle() async {
        let ride = SampleData.rides[0]
        let viewModel = RideDetailViewModel(
            ride: ride,
            rideService: PreviewRideService(delay: .zero, rides: [ride])
        )

        let renamed = await viewModel.renameRide(to: "   ")

        XCTAssertFalse(renamed)
        XCTAssertEqual(viewModel.ride.title, ride.title)
        XCTAssertEqual(viewModel.renameErrorMessage, "Enter a name for this ride.")
    }
}
