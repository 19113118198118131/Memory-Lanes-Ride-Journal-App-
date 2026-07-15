import Foundation

struct OfflineRoadPath: Equatable, Sendable {
    let coordinates: [Coordinate]
    let edges: [OfflineRoadEdge]
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
}

struct OfflineRoadPathfinder: Sendable {
    private static let maximumExpandedStates = 500_000
    private static let maximumRoadSpeedMetersPerSecond = 160.0 / 3.6

    func path(
        in graph: OfflineRoadGraphIndex,
        from sourceNodeID: UInt64,
        to destinationNodeID: UInt64
    ) throws -> OfflineRoadPath {
        guard graph.coordinates[sourceNodeID] != nil,
              graph.coordinates[destinationNodeID] != nil else {
            throw OfflineRoadRoutingError.cannotSnap
        }
        if sourceNodeID == destinationNodeID {
            guard let coordinate = graph.coordinates[sourceNodeID] else {
                throw OfflineRoadRoutingError.cannotSnap
            }
            return OfflineRoadPath(
                coordinates: [coordinate],
                edges: [],
                distanceMeters: 0,
                expectedTravelTime: 0
            )
        }

        let start = SearchState(nodeID: sourceNodeID, wayHistory: [])
        var queue = OfflineRoadMinHeap()
        var sequence = 0
        queue.insert(QueueEntry(priority: 0, routeCost: 0, sequence: sequence, state: start))
        var bestCost: [SearchState: TimeInterval] = [start: 0]
        var predecessor: [SearchState: SearchStep] = [:]
        var expandedStates = 0

        while let entry = queue.removeMinimum() {
            if expandedStates % 512 == 0 { try Task.checkCancellation() }
            guard let currentCost = bestCost[entry.state],
                  entry.routeCost <= currentCost + 0.000_001 else { continue }
            if entry.state.nodeID == destinationNodeID {
                return try reconstruct(
                    destination: entry.state,
                    start: start,
                    predecessor: predecessor,
                    graph: graph
                )
            }
            expandedStates += 1
            guard expandedStates <= Self.maximumExpandedStates else {
                throw OfflineRoadRoutingError.searchLimitReached
            }

            for edge in graph.outgoingEdges[entry.state.nodeID] ?? [] {
                guard permits(edge, from: entry.state, graph: graph) else { continue }
                let nextState = SearchState(
                    nodeID: edge.destinationNodeID,
                    wayHistory: updatedHistory(
                        entry.state.wayHistory,
                        adding: edge.wayID,
                        maximumCount: graph.maximumWayHistoryCount
                    )
                )
                let nextCost = currentCost + edge.expectedTravelTime
                if nextCost + 0.000_001 < (bestCost[nextState] ?? .infinity) {
                    bestCost[nextState] = nextCost
                    predecessor[nextState] = SearchStep(previous: entry.state, edge: edge)
                    sequence += 1
                    queue.insert(
                        QueueEntry(
                            priority: nextCost + heuristic(
                                from: edge.destinationNodeID,
                                to: destinationNodeID,
                                graph: graph
                            ),
                            routeCost: nextCost,
                            sequence: sequence,
                            state: nextState
                        )
                    )
                }
            }
        }
        throw OfflineRoadRoutingError.noPath
    }

    private func permits(
        _ edge: OfflineRoadEdge,
        from state: SearchState,
        graph: OfflineRoadGraphIndex
    ) -> Bool {
        guard let incomingWay = state.wayHistory.last else { return true }
        for restriction in graph.nodeRestrictions[state.nodeID] ?? [] where restriction.fromWayID == incomingWay {
            switch restriction.kind {
            case .prohibited where edge.wayID == restriction.toWayID:
                return false
            case .only where edge.wayID != restriction.toWayID:
                return false
            default:
                break
            }
        }

        for restriction in graph.wayRestrictions[incomingWay] ?? [] {
            let requiredHistory = [restriction.fromWayID] + restriction.viaWayIDs
            guard state.wayHistory.suffix(requiredHistory.count).elementsEqual(requiredHistory) else { continue }
            if edge.wayID == incomingWay { continue }
            switch restriction.kind {
            case .prohibited where edge.wayID == restriction.toWayID:
                return false
            case .only where edge.wayID != restriction.toWayID:
                return false
            default:
                break
            }
        }
        return true
    }

    private func updatedHistory(_ history: [UInt64], adding wayID: UInt64, maximumCount: Int) -> [UInt64] {
        guard history.last != wayID else { return history }
        var value = history
        value.append(wayID)
        if value.count > maximumCount {
            value.removeFirst(value.count - maximumCount)
        }
        return value
    }

    private func heuristic(
        from sourceNodeID: UInt64,
        to destinationNodeID: UInt64,
        graph: OfflineRoadGraphIndex
    ) -> TimeInterval {
        guard let source = graph.coordinates[sourceNodeID],
              let destination = graph.coordinates[destinationNodeID] else { return 0 }
        return OfflineRoadGeometry.distanceMeters(source, destination)
            / Self.maximumRoadSpeedMetersPerSecond
    }

    private func reconstruct(
        destination: SearchState,
        start: SearchState,
        predecessor: [SearchState: SearchStep],
        graph: OfflineRoadGraphIndex
    ) throws -> OfflineRoadPath {
        var state = destination
        var reversedEdges: [OfflineRoadEdge] = []
        while state != start {
            guard let step = predecessor[state] else { throw OfflineRoadRoutingError.noPath }
            reversedEdges.append(step.edge)
            state = step.previous
        }
        let edges = reversedEdges.reversed()
        guard let first = graph.coordinates[start.nodeID] else { throw OfflineRoadRoutingError.invalidArchive }
        var coordinates = [first]
        var distanceMeters: Double = 0
        var expectedTravelTime: TimeInterval = 0
        for edge in edges {
            guard let coordinate = graph.coordinates[edge.destinationNodeID] else {
                throw OfflineRoadRoutingError.invalidArchive
            }
            coordinates.append(coordinate)
            distanceMeters += edge.distanceMeters
            expectedTravelTime += edge.expectedTravelTime
        }
        return OfflineRoadPath(
            coordinates: coordinates,
            edges: Array(edges),
            distanceMeters: distanceMeters,
            expectedTravelTime: expectedTravelTime
        )
    }
}

private struct SearchState: Hashable, Sendable {
    let nodeID: UInt64
    let wayHistory: [UInt64]
}

private struct SearchStep: Sendable {
    let previous: SearchState
    let edge: OfflineRoadEdge
}

private struct QueueEntry: Sendable {
    let priority: Double
    let routeCost: Double
    let sequence: Int
    let state: SearchState

    func precedes(_ other: QueueEntry) -> Bool {
        priority == other.priority ? sequence < other.sequence : priority < other.priority
    }
}

private struct OfflineRoadMinHeap: Sendable {
    private var storage: [QueueEntry] = []

    mutating func insert(_ value: QueueEntry) {
        storage.append(value)
        var index = storage.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard storage[index].precedes(storage[parent]) else { break }
            storage.swapAt(index, parent)
            index = parent
        }
    }

    mutating func removeMinimum() -> QueueEntry? {
        guard !storage.isEmpty else { return nil }
        if storage.count == 1 { return storage.removeLast() }
        let value = storage[0]
        storage[0] = storage.removeLast()
        var index = 0
        while true {
            let left = index * 2 + 1
            let right = left + 1
            var candidate = index
            if left < storage.count, storage[left].precedes(storage[candidate]) { candidate = left }
            if right < storage.count, storage[right].precedes(storage[candidate]) { candidate = right }
            guard candidate != index else { break }
            storage.swapAt(index, candidate)
            index = candidate
        }
        return value
    }
}
