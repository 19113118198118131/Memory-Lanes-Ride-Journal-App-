import Combine
import Foundation

protocol GroupLiveLocationServing: Sendable {
    func setSharing(_ enabled: Bool, shareToken: UUID) async throws -> GroupLiveSharingReceipt
    func publish(_ point: RecordingPoint, shareToken: UUID) async throws
    func fetchRiders(shareToken: UUID) async throws -> [GroupLiveRider]
}

struct GroupLiveLocationService: GroupLiveLocationServing, Sendable {
    var client = SupabaseHTTPClient()
    var accessToken: @Sendable () async -> String?

    func setSharing(_ enabled: Bool, shareToken: UUID) async throws -> GroupLiveSharingReceipt {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        return try await client.post(
            path: "rest/v1/rpc/set_group_live_sharing",
            body: SharingPayload(token: shareToken, enabled: enabled),
            accessToken: token
        )
    }

    func publish(_ point: RecordingPoint, shareToken: UUID) async throws {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let didPublish: Bool = try await client.post(
            path: "rest/v1/rpc/publish_group_live_position",
            body: PositionPayload(
                token: shareToken,
                latitude: point.latitude,
                longitude: point.longitude,
                speedKmH: point.speedMetersPerSecond * 3.6
            ),
            accessToken: token
        )
        guard didPublish else { throw GroupLiveLocationError.publishRejected }
    }

    func fetchRiders(shareToken: UUID) async throws -> [GroupLiveRider] {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        return try await client.post(
            path: "rest/v1/rpc/get_group_live_riders",
            body: GroupLiveTokenPayload(token: shareToken),
            accessToken: token
        )
    }
}

enum GroupLiveLocationError: LocalizedError {
    case publishRejected

    var errorDescription: String? {
        switch self {
        case .publishRejected:
            "Your position could not be shared with the group. Ride recording is still active."
        }
    }
}

private struct SharingPayload: Encodable {
    let token: UUID
    let enabled: Bool
}

private struct PositionPayload: Encodable {
    let token: UUID
    let latitude: Double
    let longitude: Double
    let speedKmH: Double

    enum CodingKeys: String, CodingKey {
        case token
        case latitude = "lat"
        case longitude = "lng"
        case speedKmH = "speed_kmh"
    }
}

private struct GroupLiveTokenPayload: Encodable {
    let token: UUID
}

/// Serialises and throttles network writes away from the recorder's main-actor
/// location callback. Ten-second updates are sufficient for group awareness
/// while keeping battery and mobile-data use modest.
actor GroupLivePositionPublisher {
    private let service: any GroupLiveLocationServing
    private let shareToken: UUID
    private let minimumInterval: TimeInterval
    private var lastAttemptAt: Date?

    init(
        service: any GroupLiveLocationServing,
        shareToken: UUID,
        minimumInterval: TimeInterval = 10
    ) {
        self.service = service
        self.shareToken = shareToken
        self.minimumInterval = minimumInterval
    }

    @discardableResult
    func offer(_ point: RecordingPoint, now: Date = Date()) async throws -> Bool {
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < minimumInterval {
            return false
        }
        lastAttemptAt = now
        try await service.publish(point, shareToken: shareToken)
        return true
    }

    func reset() {
        lastAttemptAt = nil
    }
}

@MainActor
final class GroupLiveSharingController: ObservableObject {
    enum Status: Equatable {
        case unavailable
        case inactive
        case starting
        case sharing(expiresAt: Date?)
        case failed(message: String)
        case stopping
        case stopped
    }

    enum RiderMapStatus: Equatable {
        case unavailable
        case loading
        case live
        case offline
    }

    @Published private(set) var status: Status
    @Published private(set) var riders: [GroupLiveRider] = []
    @Published private(set) var riderMapStatus: RiderMapStatus

    let context: GroupRideRecordingContext?
    private let service: any GroupLiveLocationServing
    private let publisher: GroupLivePositionPublisher?
    private var sessionIsActive = true

    init(
        context: GroupRideRecordingContext?,
        service: any GroupLiveLocationServing
    ) {
        self.context = context
        self.service = service
        riderMapStatus = context == nil ? .unavailable : .loading
        if let context, context.shareLiveLocation {
            status = .inactive
            publisher = GroupLivePositionPublisher(service: service, shareToken: context.shareToken)
        } else {
            status = .unavailable
            publisher = nil
        }
    }

    var isVisible: Bool {
        context != nil && sessionIsActive
    }

    var isSharing: Bool {
        if case .sharing = status { return true }
        return false
    }

    var canStopSharing: Bool {
        switch status {
        case .starting, .sharing, .failed:
            context?.shareLiveLocation == true
        case .unavailable, .inactive, .stopping, .stopped:
            false
        }
    }

    func start() async {
        guard let context, sessionIsActive else { return }
        if context.shareLiveLocation, status != .starting {
            status = .starting
            do {
                let receipt = try await service.setSharing(true, shareToken: context.shareToken)
                guard sessionIsActive else {
                    _ = try? await service.setSharing(false, shareToken: context.shareToken)
                    status = .stopped
                    return
                }
                guard receipt.enabled else {
                    status = .failed(message: "Group sharing could not be enabled. Ride recording is still active.")
                    await refreshRiders()
                    return
                }
                await publisher?.reset()
                status = .sharing(expiresAt: receipt.expiresAt)
            } catch {
                status = .failed(message: Self.message(for: error))
            }
        }
        await refreshRiders()
    }

    func offer(_ point: RecordingPoint) async {
        guard isSharing, let publisher else { return }
        do {
            try await publisher.offer(point)
        } catch {
            guard isSharing else { return }
            status = .failed(message: Self.message(for: error))
        }
    }

    func stop() async {
        guard let context, context.shareLiveLocation else { return }
        guard status != .stopped, status != .unavailable, status != .stopping else { return }
        status = .stopping
        _ = try? await service.setSharing(false, shareToken: context.shareToken)
        status = .stopped
    }

    func observeRiders() async {
        guard context != nil else { return }
        while !Task.isCancelled, sessionIsActive {
            await refreshRiders()
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
        }
    }

    func refreshRiders(now: Date = Date()) async {
        guard let context, sessionIsActive else { return }
        if riders.isEmpty {
            riderMapStatus = .loading
        }
        do {
            let fetchedRiders = try await service.fetchRiders(shareToken: context.shareToken)
            guard sessionIsActive else { return }
            riders = fetchedRiders
                .filter { $0.isFresh(at: now) }
            riderMapStatus = .live
        } catch is CancellationError {
        } catch {
            riders = riders.filter { $0.isFresh(at: now) }
            riderMapStatus = .offline
        }
    }

    func endSession() async {
        guard sessionIsActive else { return }
        sessionIsActive = false
        await stop()
        riders = []
        riderMapStatus = .unavailable
    }

    private static func message(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return "Group sharing is offline. Ride recording is still active."
    }
}
