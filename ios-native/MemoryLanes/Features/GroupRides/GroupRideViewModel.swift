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
    private(set) var pendingCheckIn: Bool?
    private(set) var isPostingAnnouncement = false
    private(set) var didLeaveRide = false
    private(set) var didCloseRide = false
    var errorMessage: String?

    let shareToken: UUID
    private let service: GroupRideServing
    private let notificationCoordinator: NotificationCoordinator

    init(
        shareToken: UUID,
        service: GroupRideServing,
        notificationCoordinator: NotificationCoordinator = .shared
    ) {
        self.shareToken = shareToken
        self.service = service
        self.notificationCoordinator = notificationCoordinator
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
            let groupRide = try await service.fetchGroupRide(shareToken: shareToken)
            state = .loaded(groupRide)
            await notificationCoordinator.reconcileReminder(for: groupRide)
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
            let groupRide = try await service.setRSVP(rsvp, shareToken: shareToken)
            state = .loaded(groupRide)
            await notificationCoordinator.reconcileReminder(for: groupRide)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func setCheckIn(_ checkedIn: Bool) async -> Bool {
        guard let groupRide, groupRide.checkInAvailable, !isWorking else { return false }
        isWorking = true
        pendingCheckIn = checkedIn
        errorMessage = nil
        defer {
            pendingCheckIn = nil
            isWorking = false
        }
        do {
            state = .loaded(try await service.setCheckIn(checkedIn, shareToken: shareToken))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func postAnnouncement(_ message: String) async -> Bool {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groupRide, groupRide.isOwner, !cleanMessage.isEmpty, !isWorking else { return false }
        isWorking = true
        isPostingAnnouncement = true
        errorMessage = nil
        defer {
            isPostingAnnouncement = false
            isWorking = false
        }
        do {
            state = .loaded(try await service.postAnnouncement(cleanMessage, shareToken: shareToken))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func prepareToStartRoute() async -> Bool {
        guard let groupRide else { return false }
        if !groupRide.isOwner, groupRide.yourRSVP != .going {
            guard await setRSVP(.going) else { return false }
        }
        if let refreshed = self.groupRide,
           refreshed.checkInAvailable,
           !refreshed.isCheckedIn {
            _ = await setCheckIn(true)
        }
        return true
    }

    func updateGroupRide(_ draft: GroupRideDraft) async -> Bool {
        guard let groupRide, groupRide.isOwner, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await service.updateGroupRide(
                shareToken: shareToken,
                groupRideID: groupRide.id,
                draft: draft
            )
            state = .loaded(updated)
            await notificationCoordinator.reconcileReminder(for: updated)
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
            await notificationCoordinator.reconcileReminder(for: groupRide.withoutMembership)
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
            let updated = try await service.setStatus(status, shareToken: shareToken)
            state = .loaded(updated)
            await notificationCoordinator.reconcileReminder(for: updated)
            didCloseRide = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
