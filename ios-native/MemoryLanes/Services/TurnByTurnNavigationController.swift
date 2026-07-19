import AVFoundation
import Combine
import Foundation

enum TurnByTurnSessionState: Equatable {
    case inactive
    case loading
    case navigating
    case rerouting
    case unavailable(String)
    case arrived
}

@MainActor
protocol NavigationSpeaking: AnyObject {
    func speak(_ message: String)
    func stop()
}

@MainActor
final class SystemNavigationSpeaker: NSObject, NavigationSpeaking, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ message: String) {
        guard !message.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try? session.setActive(true, options: [])
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-NZ")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        releaseAudioSession()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        releaseAudioSession()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        releaseAudioSession()
    }

    private func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}

struct NavigationAnnouncementPolicy: Sendable {
    private var instructionID: Int?
    private var spokenThresholds: Set<Int> = []
    private var lastState: NavigationRouteState?

    mutating func announcement(for snapshot: TurnByTurnSnapshot) -> String? {
        defer { lastState = snapshot.state }
        if snapshot.state == .arrived, lastState != .arrived {
            return "You have arrived at your destination."
        }
        if snapshot.state == .offRoute, lastState != .offRoute {
            return "You are off route. Finding a safe return."
        }
        guard snapshot.state == .onRoute || snapshot.state == .nearRoute,
              let instruction = snapshot.instruction,
              let distance = snapshot.distanceToManeuverMeters else {
            return nil
        }

        if instructionID != instruction.id {
            instructionID = instruction.id
            spokenThresholds.removeAll()
        }
        let thresholds = [1_000, 300, 80]
        guard let threshold = thresholds.filter({ distance <= Double($0) }).min(),
              !spokenThresholds.contains(threshold) else {
            return nil
        }
        spokenThresholds.insert(threshold)
        if threshold <= 80 {
            return "Now, \(instruction.spokenText)."
        }
        let distanceText = threshold >= 1_000 ? "one kilometre" : "\(threshold) metres"
        return "In \(distanceText), \(instruction.spokenText)."
    }
}

@MainActor
final class TurnByTurnNavigationController: ObservableObject {
    @Published private(set) var state: TurnByTurnSessionState = .inactive
    @Published private(set) var snapshot: TurnByTurnSnapshot?
    @Published private(set) var routeCoordinates: [Coordinate] = []
    @Published var isVoiceEnabled = true {
        didSet {
            if !isVoiceEnabled { speaker.stop() }
        }
    }

    private let plannedRoute: PlannedRoute?
    private let provider: any TurnByTurnRouteProviding
    private let speaker: any NavigationSpeaking
    private var engine: TurnByTurnNavigationEngine?
    private var announcementPolicy = NavigationAnnouncementPolicy()
    private var preparationTask: Task<Void, Never>?
    private var rerouteTask: Task<Void, Never>?
    private var offRouteSince: Date?
    private var lastRerouteAt: Date?

    init(
        plannedRoute: PlannedRoute?,
        provider: any TurnByTurnRouteProviding = MapKitTurnByTurnRouteProvider(),
        speaker: any NavigationSpeaking = SystemNavigationSpeaker()
    ) {
        self.plannedRoute = plannedRoute
        self.provider = provider
        self.speaker = speaker
        routeCoordinates = plannedRoute?.route ?? []
    }

    deinit {
        preparationTask?.cancel()
        rerouteTask?.cancel()
    }

    func prepare(startingAt coordinate: Coordinate?) {
        guard let plannedRoute, preparationTask == nil, engine == nil else { return }
        let base = plannedRoute.waypoints.count > 1 ? plannedRoute.waypoints : plannedRoute.route
        guard base.count > 1 else {
            state = .unavailable(TurnByTurnNavigationError.invalidRoute.localizedDescription)
            return
        }
        var waypoints = base
        if let coordinate, let first = waypoints.first,
           Self.distanceMeters(coordinate, first) > 150 {
            waypoints.insert(coordinate, at: 0)
        }
        state = .loading
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let route = try await provider.route(through: waypoints)
                try Task.checkCancellation()
                activate(route)
            } catch is CancellationError {
                return
            } catch {
                state = .unavailable(error.localizedDescription)
            }
            preparationTask = nil
        }
    }

    func update(_ point: RecordingPoint) {
        if engine == nil {
            prepare(startingAt: point.coordinate)
            return
        }
        guard var nextEngine = engine else { return }
        let nextSnapshot = nextEngine.update(coordinate: point.coordinate)
        engine = nextEngine
        snapshot = nextSnapshot
        state = nextSnapshot.state == .arrived ? .arrived : .navigating
        if isVoiceEnabled, let message = announcementPolicy.announcement(for: nextSnapshot) {
            speaker.speak(message)
        }
        updateRerouting(for: nextSnapshot, point: point)
    }

    func cancel() {
        preparationTask?.cancel()
        rerouteTask?.cancel()
        speaker.stop()
    }

    private func activate(_ route: TurnByTurnRoute) {
        do {
            engine = try TurnByTurnNavigationEngine(route: route)
            routeCoordinates = route.coordinates
            state = .navigating
            offRouteSince = nil
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    private func updateRerouting(for snapshot: TurnByTurnSnapshot, point: RecordingPoint) {
        guard snapshot.state == .offRoute else {
            offRouteSince = nil
            return
        }
        let now = point.timestamp
        if offRouteSince == nil { offRouteSince = now }
        guard let offRouteSince,
              now.timeIntervalSince(offRouteSince) >= 12,
              lastRerouteAt.map({ now.timeIntervalSince($0) >= 45 }) ?? true,
              rerouteTask == nil,
              let plannedRoute else {
            return
        }

        let waypoints = NavigationRecoveryPlanner.waypoints(
            from: point.coordinate,
            plannedRoute: plannedRoute,
            progressPercent: snapshot.progressPercent
        )
        guard waypoints.count > 1 else { return }
        state = .rerouting
        lastRerouteAt = now
        rerouteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let route = try await provider.route(through: waypoints)
                try Task.checkCancellation()
                activate(route)
            } catch is CancellationError {
                return
            } catch {
                state = .navigating
            }
            rerouteTask = nil
        }
    }

    private static func distanceMeters(_ first: Coordinate, _ second: Coordinate) -> Double {
        let latitudeScale = 111_132.0
        let longitudeScale = 111_320.0 * cos(first.latitude * .pi / 180)
        return hypot(
            (second.longitude - first.longitude) * longitudeScale,
            (second.latitude - first.latitude) * latitudeScale
        )
    }
}
