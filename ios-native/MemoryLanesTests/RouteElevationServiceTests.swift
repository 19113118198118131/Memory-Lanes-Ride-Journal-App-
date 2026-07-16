import Foundation
import Testing
@testable import MemoryLanes

struct RouteElevationServiceTests {
    @Test func positiveGainSumsOnlyClimbs() {
        // +20, -10 (ignored), +20, 0 (ignored) => 40
        let elevations = [100.0, 120.0, 110.0, 130.0, 130.0]
        #expect(OpenMeteoElevationService.positiveGain(elevations) == 40)
    }

    @Test func descentOnlyRouteHasNoGain() {
        #expect(OpenMeteoElevationService.positiveGain([300, 250, 200, 150]) == 0)
    }

    @Test func sparseSamplesAreHandled() {
        #expect(OpenMeteoElevationService.positiveGain([]) == 0)
        #expect(OpenMeteoElevationService.positiveGain([420]) == 0)
    }
}
