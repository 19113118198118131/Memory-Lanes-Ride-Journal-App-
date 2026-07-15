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
    private(set) var didLeaveRide = false
    private(set) var didCloseRide = false
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
        await refresh(showFailure: true)
    }

    func refresh() async {
        await refresh(showFailure: true)
    }

    func observeChanges() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await refresh(showFailure: false)
        }
    }

    private func refresh(showFailure: Bool) async {
        do {
            state = .loaded(try await service.fetchGroupRide(shareToken: shareToken))
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            if showFailure || groupRide == nil {
                state = .failed(error.localizedDescription)
            }
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

    func updateGroupRide(_ draft: GroupRideDraft) async -> Bool {
        guard let groupRide, groupRide.isOwner, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            state = .loaded(
                try await service.updateGroupRide(
                    shareToken: shareToken,
                    groupRideID: groupRide.id,
                    draft: draft
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func leaveRide() async -> Bool {
        guard let groupRide, !groupRide.isOwner, groupRide.isMember, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.leaveGroupRide(shareToken: shareToken)
            didLeaveRide = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setStatus(_ status: GroupRideStatus) async -> Bool {
        guard let groupRide, groupRide.isOwner, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            state = .loaded(try await service.setStatus(status, shareToken: shareToken))
            didCloseRide = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
