import Foundation

struct OfflineTurnByTurnRouteProvider: TurnByTurnRouteProviding {
    private let roadProvider: OfflineRoadRouteProvider

    init(roadProvider: OfflineRoadRouteProvider = OfflineRoadRouteProvider()) {
        self.roadProvider = roadProvider
    }

    func route(through waypoints: [Coordinate]) async throws -> TurnByTurnRoute {
        guard waypoints.count > 1 else { throw TurnByTurnNavigationError.invalidRoute }
        let path = try await roadProvider.navigationPath(through: waypoints)
        return try OfflineManeuverBuilder().route(from: path)
    }
}

struct OfflineFirstTurnByTurnRouteProvider: TurnByTurnRouteProviding {
    private let offline: any TurnByTurnRouteProviding
    private let fallback: any TurnByTurnRouteProviding

    init(
        offline: any TurnByTurnRouteProviding = OfflineTurnByTurnRouteProvider(),
        fallback: any TurnByTurnRouteProviding = MapKitTurnByTurnRouteProvider()
    ) {
        self.offline = offline
        self.fallback = fallback
    }

    func route(through waypoints: [Coordinate]) async throws -> TurnByTurnRoute {
        do {
            return try await offline.route(through: waypoints)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.route(through: waypoints)
        }
    }
}

struct OfflineManeuverBuilder: Sendable {
    func route(from path: OfflineNavigationPath) throws -> TurnByTurnRoute {
        let coordinates = path.route.coordinates
        let edges = path.edges
        guard coordinates.count > 1,
              edges.count == coordinates.count - 1 else {
            throw TurnByTurnNavigationError.noRoute
        }

        var instructions = [startInstruction(edge: edges[0], coordinates: coordinates)]
        var distanceMeters = edges[0].distanceMeters
        for index in edges.indices.dropFirst() {
            try Task.checkCancellation()
            let previous = edges[index - 1]
            let current = edges[index]
            if let instruction = transitionInstruction(
                previous: previous,
                current: current,
                previousCoordinate: coordinates[index - 1],
                junctionCoordinate: coordinates[index],
                nextCoordinate: coordinates[index + 1],
                startsAtMeters: distanceMeters,
                id: instructions.count
            ) {
                instructions.append(instruction)
            }
            distanceMeters += current.distanceMeters
        }
        instructions.append(
            NavigationInstruction(
                id: instructions.count,
                text: "Arrive at your destination",
                notice: nil,
                maneuver: .arrive,
                startsAtMeters: path.route.distanceMeters
            )
        )

        return TurnByTurnRoute(
            coordinates: coordinates,
            distanceMeters: path.route.distanceMeters,
            expectedTravelTime: path.route.expectedTravelTime,
            instructions: instructions
        )
    }

    private func startInstruction(
        edge: OfflineRoadEdge,
        coordinates: [Coordinate]
    ) -> NavigationInstruction {
        let direction = cardinalDirection(from: coordinates[0], to: coordinates[1])
        let roadName = cleanName(edge.name)
        let text = roadName.map { "Head \(direction) on \($0)" } ?? "Head \(direction) on the route"
        return NavigationInstruction(
            id: 0,
            text: text,
            notice: nil,
            maneuver: .start,
            startsAtMeters: 0
        )
    }

    private func transitionInstruction(
        previous: OfflineRoadEdge,
        current: OfflineRoadEdge,
        previousCoordinate: Coordinate,
        junctionCoordinate: Coordinate,
        nextCoordinate: Coordinate,
        startsAtMeters: Double,
        id: Int
    ) -> NavigationInstruction? {
        let previousName = cleanName(previous.name)
        let currentName = cleanName(current.name)
        let changesRoad = previous.wayID != current.wayID
        let changesName = currentName != nil && currentName != previousName
        guard changesRoad || changesName else { return nil }

        let delta = signedTurnAngle(
            incomingFrom: previousCoordinate,
            junction: junctionCoordinate,
            outgoingTo: nextCoordinate
        )
        let maneuver = maneuver(for: delta, roadName: currentName)
        guard changesName || abs(delta) >= 32 else { return nil }
        let text = instructionText(for: maneuver, roadName: currentName)
        return NavigationInstruction(
            id: id,
            text: text,
            notice: nil,
            maneuver: maneuver,
            startsAtMeters: startsAtMeters
        )
    }

    private func maneuver(for delta: Double, roadName: String?) -> NavigationManeuver {
        if roadName?.localizedCaseInsensitiveContains("roundabout") == true {
            return .roundabout
        }
        let magnitude = abs(delta)
        if magnitude >= 150 { return delta >= 0 ? .uTurnRight : .uTurnLeft }
        if magnitude >= 105 { return delta >= 0 ? .sharpRight : .sharpLeft }
        if magnitude >= 42 { return delta >= 0 ? .right : .left }
        if magnitude >= 18 { return delta >= 0 ? .slightRight : .slightLeft }
        return .straight
    }

    private func instructionText(for maneuver: NavigationManeuver, roadName: String?) -> String {
        let destination = roadName.map { " onto \($0)" } ?? ""
        return switch maneuver {
        case .slightLeft: "Bear left\(destination)"
        case .left: "Turn left\(destination)"
        case .sharpLeft: "Turn sharp left\(destination)"
        case .slightRight: "Bear right\(destination)"
        case .right: "Turn right\(destination)"
        case .sharpRight: "Turn sharp right\(destination)"
        case .uTurnLeft, .uTurnRight: "Make a U-turn\(destination)"
        case .roundabout: roadName.map { "Continue through the roundabout onto \($0)" }
            ?? "Continue through the roundabout"
        default: roadName.map { "Continue onto \($0)" } ?? "Continue on the route"
        }
    }

    private func signedTurnAngle(
        incomingFrom: Coordinate,
        junction: Coordinate,
        outgoingTo: Coordinate
    ) -> Double {
        let incoming = bearing(from: incomingFrom, to: junction)
        let outgoing = bearing(from: junction, to: outgoingTo)
        var delta = outgoing - incoming
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return delta
    }

    private func bearing(from source: Coordinate, to destination: Coordinate) -> Double {
        let sourceLatitude = source.latitude * .pi / 180
        let destinationLatitude = destination.latitude * .pi / 180
        let longitudeDelta = (destination.longitude - source.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(sourceLatitude) * sin(destinationLatitude)
            - sin(sourceLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        return atan2(y, x) * 180 / .pi
    }

    private func cardinalDirection(from source: Coordinate, to destination: Coordinate) -> String {
        let value = (bearing(from: source, to: destination) + 360).truncatingRemainder(dividingBy: 360)
        let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return directions[Int(((value + 22.5) / 45).rounded(.down)) % directions.count]
    }

    private func cleanName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
