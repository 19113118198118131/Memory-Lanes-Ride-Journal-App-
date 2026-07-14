import Foundation
import Observation

@MainActor
@Observable
final class GroupRideViewModel {
    enum LoadState {
        case loading
        case loaded(GroupRide)
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var isWorking = false
    private(set) var pendingRSVP: GroupRideRSVP?
    private(set) var didEndRide = false
    var errorMessage: String?

    let shareToken: UUID
    private let service: GroupRideServing

    init(shareToken: UUID, service: GroupRideServing) {
        self.shareToken = shareToken
        self.service = service
    }

    var groupRide: GroupRide? {
        if case .loaded(let groupRide) = state { return groupRide }
        return nil
    }

    func load() async {
        state = .loading
        await refresh()
    }

    func refresh() async {
        do {
            state = .loaded(try await service.fetchGroupRide(shareToken: shareToken))
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func setRSVP(_ rsvp: GroupRideRSVP) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        pendingRSVP = rsvp
        errorMessage = nil
        defer {
            pendingRSVP = nil
            isWorking = false
        }
        do {
            state = .loaded(try await service.setRSVP(rsvp, shareToken: shareToken))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func updateMeeting(meetTime: Date?, meetPoint: String?) async -> Bool {
        guard let groupRide, groupRide.isOwner, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            state = .loaded(
                try await service.updateMeeting(
                    shareToken: shareToken,
                    groupRideID: groupRide.id,
                    meetTime: meetTime,
                    meetPoint: meetPoint
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func endRide() async -> Bool {
        guard let groupRide, groupRide.isOwner, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.endGroupRide(groupRide)
            didEndRide = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
