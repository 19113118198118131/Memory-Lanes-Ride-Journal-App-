import Foundation

// MARK: - RoutePreviewLoader
//
// A process-wide cache for ride-thumbnail polylines, keyed by GPX path. The
// dashboard and stats screens both draw route previews, so caching here means a
// ride's GPX is downloaded and decimated at most once per session, no matter how
// many screens show it. The actor serialises cache access; the actual download +
// parse happens inside the (off-main) `RideServing`.

actor RoutePreviewLoader {
    static let shared = RoutePreviewLoader()

    private var cache: [String: [Coordinate]] = [:]

    func preview(for ride: Ride, using service: any RideServing) async -> [Coordinate] {
        guard let key = ride.gpxPath else { return [] }
        if let hit = cache[key] { return hit }
        let preview = (try? await service.routePreview(for: ride)) ?? []
        if !preview.isEmpty { cache[key] = preview }
        return preview
    }
}

// MARK: - RidePreviewHydration
//
// Fills in missing route thumbnails for a list of rides with bounded
// concurrency, calling `apply` on the main actor as each preview arrives so the
// list fills in progressively instead of blocking on the whole batch.

@MainActor
enum RidePreviewHydration {
    static func run(
        for rides: [Ride],
        using service: any RideServing,
        maxConcurrent: Int = 4,
        apply: (UUID, [Coordinate]) -> Void
    ) async {
        // Only rides that have a GPX file but no preview yet need loading.
        let targets = rides.filter { $0.routePreview.count <= 1 && $0.gpxPath != nil }
        guard !targets.isEmpty else { return }

        let loader = RoutePreviewLoader.shared
        await withTaskGroup(of: (UUID, [Coordinate]).self) { group in
            var next = 0
            func enqueueNext() {
                guard next < targets.count else { return }
                let ride = targets[next]
                next += 1
                group.addTask { (ride.id, await loader.preview(for: ride, using: service)) }
            }

            // Prime the pump with `maxConcurrent` in-flight loads, then feed a
            // new one each time one finishes — a simple bounded window.
            for _ in 0..<min(maxConcurrent, targets.count) { enqueueNext() }
            for await (id, preview) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if !preview.isEmpty { apply(id, preview) }
                enqueueNext()
            }
        }
    }
}
