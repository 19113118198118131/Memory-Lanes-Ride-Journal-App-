import SwiftUI

struct GroupRideLobbyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: GroupRideViewModel
    @State private var activityPayload: ActivityPayload?
    @State private var showingMeetingEditor = false
    @State private var pendingStatus: GroupRideStatus?
    @State private var showingLeaveConfirmation = false
    @State private var showAllAttendees = false
    @State private var showAllAnnouncements = false
    @State private var showingAnnouncementComposer = false
    @State private var pendingStartRide: GroupRide?

    let onStartRoute: (PlannedRoute, GroupRideRecordingContext) -> Void
    let onEnded: () -> Void

    init(
        viewModel: GroupRideViewModel,
        onStartRoute: @escaping (PlannedRoute, GroupRideRecordingContext) -> Void = { _, _ in },
        onEnded: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onStartRoute = onStartRoute
        self.onEnded = onEnded
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingState
            case .failed(let message):
                EmptyState(
                    systemImage: "person.3.sequence.fill",
                    title: "Group ride unavailable",
                    message: message,
                    actionTitle: "Try Again"
                ) {
                    Task { await viewModel.load() }
                }
                .mlScreenPadding()
            case .loaded(let groupRide):
                lobby(groupRide)
            }
        }
        .background(Color.mlBackground)
        .navigationTitle("Group Ride")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
            await viewModel.observeChanges()
        }
        .sheet(item: $activityPayload) { payload in
            ActivityView(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingMeetingEditor) {
            if let groupRide = viewModel.groupRide {
                GroupRideMeetingEditor(groupRide: groupRide, isSaving: viewModel.isWorking) { draft in
                    let saved = await viewModel.updateGroupRide(draft)
                    if saved {
                        Haptics.success()
                        showingMeetingEditor = false
                    } else {
                        Haptics.error()
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingAnnouncementComposer) {
            GroupRideAnnouncementComposer { message in
                await viewModel.postAnnouncement(message)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingStartRide) { groupRide in
            GroupRideStartSheet(groupRide: groupRide) { shareLiveLocation in
                guard await viewModel.prepareToStartRoute() else {
                    Haptics.error()
                    return false
                }
                let context = GroupRideRecordingContext(
                    shareToken: groupRide.shareToken,
                    title: groupRide.title,
                    shareLiveLocation: shareLiveLocation
                )
                Haptics.success()
                onStartRoute(groupRide.plannedRoute, context)
                return true
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            pendingStatus == .completed ? "Mark this ride complete?" : "Cancel this group ride?",
            isPresented: Binding(
                get: { pendingStatus != nil },
                set: { if !$0 { pendingStatus = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let status = pendingStatus {
                Button(status == .completed ? "Mark Complete" : "Cancel Group Ride", role: status == .cancelled ? .destructive : nil) {
                    pendingStatus = nil
                    Task {
                        if await viewModel.setStatus(status) {
                            Haptics.success()
                            onEnded()
                        } else {
                            Haptics.error()
                        }
                    }
                }
            }
            Button("Keep Ride", role: .cancel) { pendingStatus = nil }
        } message: {
            Text(pendingStatus == .completed
                ? "The ride moves out of everyone's upcoming list and remains recorded as completed."
                : "The invitation closes and the ride moves out of everyone's upcoming list.")
        }
        .confirmationDialog(
            "Leave this group ride?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Group Ride", role: .destructive) {
                Task {
                    if await viewModel.leaveRide() {
                        Haptics.success()
                        onEnded()
                    } else {
                        Haptics.error()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your RSVP is removed. You can join again later with the invitation while the ride is still open.")
        }
    }

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                SkeletonBar(height: 300, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 130, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 180, radius: Radius.card).mlShimmer()
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
    }

    private func lobby(_ groupRide: GroupRide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if groupRide.route.count > 1 {
                    MLMapView(route: groupRide.route, fadeColor: .mlBackground)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .mlStaggeredReveal(index: 0, distance: 8)
                }

                header(groupRide)
                    .mlStaggeredReveal(index: 1)

                SegmentedMetric(items: [
                    .init(value: groupRide.distanceKm.map { String(format: "%.1f", $0) } ?? "--", unit: "km", label: "Distance"),
                    .init(value: "\(groupRide.goingCount)", unit: "", label: "Riding"),
                    .init(value: capacityMetric(groupRide), unit: "", label: groupRide.capacity == nil ? "Maybe" : "Spots")
                ])
                .padding(.horizontal, Spacing.md)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                )
                .mlStaggeredReveal(index: 2)

                meetingCard(groupRide)
                    .mlStaggeredReveal(index: 3)
                if shouldShowRideDay(groupRide) {
                    rideDayCard(groupRide)
                        .mlStaggeredReveal(index: 4)
                }
                if groupRide.isOwner {
                    organiserDashboard(groupRide)
                        .mlStaggeredReveal(index: 5)
                }
                if !groupRide.announcements.isEmpty {
                    announcements(groupRide)
                        .mlStaggeredReveal(index: 6)
                }
                if !groupRide.isOwner {
                    rsvpCard(groupRide)
                        .mlStaggeredReveal(index: 7)
                }
                attendees(groupRide)
                    .mlStaggeredReveal(index: 8)
                actions(groupRide)
                    .mlStaggeredReveal(index: 9)

                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.mlDanger)
                        Text(errorMessage)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            withAnimation(reduceMotion ? nil : Motion.spring) { viewModel.clearError() }
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                        }
                        .buttonStyle(MLPressableButtonStyle())
                        .foregroundStyle(Color.mlTextSecondary)
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(.leading, Spacing.md)
                    .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .refreshable { await viewModel.refresh() }
        .animation(reduceMotion ? nil : Motion.spring, value: viewModel.errorMessage)
    }

    private func header(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(groupRide.isOwner ? "Hosting" : "Group route").mlKicker()
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text(groupRide.title)
                    .font(MLFont.displayXL)
                    .foregroundStyle(Color.mlTextPrimary)
                Spacer(minLength: Spacing.xs)
                Label(groupRide.status.title, systemImage: groupRide.status.symbol)
                    .font(MLFont.caption)
                    .foregroundStyle(statusTint(groupRide.status))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(statusTint(groupRide.status).opacity(0.12), in: Capsule())
            }
            Text(hostLine(groupRide))
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
            if let details = groupRide.details, !details.isEmpty {
                Text(details)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusTint(_ status: GroupRideStatus) -> Color {
        switch status {
        case .scheduled: .mlAccent
        case .cancelled: .mlDanger
        case .completed: .mlSuccess
        }
    }

    private func capacityMetric(_ groupRide: GroupRide) -> String {
        guard let remaining = groupRide.spotsRemaining else { return "\(groupRide.maybeCount)" }
        return "\(remaining)"
    }

    private func hostLine(_ groupRide: GroupRide) -> String {
        var parts = [groupRide.routeTitle]
        if let hostedBy = groupRide.hostedBy, !hostedBy.isEmpty {
            parts.append("Hosted by \(hostedBy)")
        }
        return parts.joined(separator: " · ")
    }

    private func meetingCard(_ groupRide: GroupRide) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(MLFont.title2)
                .foregroundStyle(Color.mlAccent)
                .frame(width: 44, height: 44)
                .background(Color.mlSurfaceElevated, in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Meet point").mlKicker()
                Text(meetingTitle(groupRide))
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                if let point = groupRide.meetPoint, !point.isEmpty {
                    Text(point)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
            }
            Spacer()
            if groupRide.isOwner {
                Button {
                    showingMeetingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(MLPressableButtonStyle())
                .foregroundStyle(Color.mlAccent)
                .accessibilityLabel("Edit meeting details")
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func meetingTitle(_ groupRide: GroupRide) -> String {
        groupRide.meetTime?.formatted(date: .abbreviated, time: .shortened) ?? "Time to be confirmed"
    }

    private func shouldShowRideDay(_ groupRide: GroupRide) -> Bool {
        groupRide.status == .scheduled && (
            groupRide.isOwner || groupRide.yourRSVP == .going || groupRide.yourRSVP == .maybe
        )
    }

    private func rideDayCard(_ groupRide: GroupRide) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: groupRide.isCheckedIn ? "checkmark.circle.fill" : "location.circle.fill")
                .font(MLFont.displaySmall)
                .foregroundStyle(groupRide.isCheckedIn ? Color.mlSuccess : Color.mlAccent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(
                    (groupRide.isCheckedIn ? Color.mlSuccess : Color.mlAccent).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(groupRide.isCheckedIn ? "You're checked in" : "Ride-day check-in")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(checkInDetail(groupRide))
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs)

            if groupRide.checkInAvailable {
                Button {
                    Task {
                        if await viewModel.setCheckIn(!groupRide.isCheckedIn) {
                            if groupRide.isCheckedIn {
                                Haptics.selection()
                            } else {
                                Haptics.success()
                            }
                        } else {
                            Haptics.error()
                        }
                    }
                } label: {
                    Group {
                        if viewModel.pendingCheckIn != nil {
                            ProgressView().tint(.mlAccent)
                        } else {
                            Text(groupRide.isCheckedIn ? "Undo" : "I'm here")
                        }
                    }
                    .font(MLFont.callout)
                    .foregroundStyle(groupRide.isCheckedIn ? Color.mlTextSecondary : Color.mlAccent)
                    .frame(minWidth: Layout.minTouchTarget, minHeight: Layout.minTouchTarget)
                }
                .buttonStyle(MLPressableButtonStyle())
                .disabled(viewModel.isWorking)
                .accessibilityValue(groupRide.isCheckedIn ? "Checked in" : "Not checked in")
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(
                    groupRide.isCheckedIn ? Color.mlSuccess.opacity(0.32) : Color.mlHairline,
                    lineWidth: Layout.hairline
                )
        }
        .animation(reduceMotion ? nil : Motion.springSnappy, value: groupRide.isCheckedIn)
    }

    private func checkInDetail(_ groupRide: GroupRide) -> String {
        if groupRide.isCheckedIn {
            return "The organiser can see that you've arrived."
        }
        if groupRide.checkInAvailable {
            return "Let the organiser know you're at the meeting point."
        }
        guard let meetTime = groupRide.meetTime else {
            return "Check-in becomes available when the host confirms the ride."
        }
        let opensAt = meetTime.addingTimeInterval(-21_600)
        if Date() < opensAt {
            return "Opens \(opensAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Check-in has closed for this ride."
    }

    private func rsvpCard(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your RSVP")
            if groupRide.status != .scheduled {
                Label("This ride is \(groupRide.status.title.lowercased()).", systemImage: groupRide.status.symbol)
                    .font(MLFont.callout)
                    .foregroundStyle(statusTint(groupRide.status))
            } else {
                HStack(spacing: Spacing.sm) {
                    ForEach(GroupRideRSVP.allCases, id: \.self) { rsvp in
                        let selected = groupRide.yourRSVP == rsvp
                        Button {
                            Task {
                                if await viewModel.setRSVP(rsvp) {
                                    Haptics.selection()
                                } else {
                                    Haptics.error()
                                }
                            }
                        } label: {
                            VStack(spacing: Spacing.xxs) {
                                if viewModel.pendingRSVP == rsvp {
                                    ProgressView()
                                        .tint(selected ? .mlOnAccent : .mlAccent)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Image(systemName: rsvp.symbol)
                                        .transition(.scale.combined(with: .opacity))
                                }
                                Text(rsvp.title)
                                    .font(MLFont.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .foregroundStyle(selected ? Color.mlOnAccent : Color.mlTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                selected ? Color.mlAccent : Color.mlSurfaceElevated,
                                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            )
                        }
                        .buttonStyle(MLPressableButtonStyle())
                        .disabled(viewModel.isWorking)
                        .accessibilityLabel(rsvp.title)
                        .accessibilityValue(viewModel.pendingRSVP == rsvp ? "Updating" : selected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.springSnappy, value: viewModel.pendingRSVP)
    }

    private func attendees(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: groupRide.isOwner ? "Rider Roster" : "Who's Coming")
            if groupRide.members.isEmpty {
                Text(groupRide.isMember || groupRide.isOwner
                    ? "No responses yet"
                    : "RSVP to see the rider list.")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
            } else {
                ForEach(Array(visibleMembers(groupRide).enumerated()), id: \.offset) { index, member in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(MLFont.title2)
                            .foregroundStyle(member.isYou ? Color.mlAccent : Color.mlTextTertiary)
                        Text(member.isYou ? "\(member.name) (you)" : member.name)
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Spacer()
                        Label(
                            member.checkedInAt == nil ? member.rsvp.title : "Checked in",
                            systemImage: member.checkedInAt == nil ? member.rsvp.symbol : "checkmark.circle.fill"
                        )
                            .font(MLFont.caption)
                            .foregroundStyle(member.checkedInAt == nil ? rsvpTint(member.rsvp) : Color.mlSuccess)
                    }
                    .padding(.vertical, Spacing.xs)
                    .mlStaggeredReveal(index: index)
                }

                if groupRide.members.count > 4 {
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : Motion.spring) {
                            showAllAttendees.toggle()
                        }
                    } label: {
                        Label(
                            showAllAttendees ? "Show fewer riders" : "Show all \(groupRide.members.count) riders",
                            systemImage: showAllAttendees ? "chevron.up" : "chevron.down"
                        )
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.minTouchTarget)
                    }
                    .buttonStyle(MLPressableButtonStyle())
                }
            }
        }
    }

    private func organiserDashboard(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Organiser Dashboard")
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Ride-day readiness").mlKicker()
                        Text(readinessTitle(groupRide))
                            .font(MLFont.title2)
                            .foregroundStyle(Color.mlTextPrimary)
                    }
                    Spacer()
                    Text("\(groupRide.checkedInCount)/\(expectedRiderCount(groupRide))")
                        .font(MLFont.title2)
                        .foregroundStyle(Color.mlAccent)
                        .monospacedDigit()
                        .accessibilityLabel("\(groupRide.checkedInCount) of \(expectedRiderCount(groupRide)) checked in")
                }

                ProgressView(
                    value: Double(groupRide.checkedInCount),
                    total: Double(max(expectedRiderCount(groupRide), 1))
                )
                .tint(.mlAccent)

                HStack(spacing: 0) {
                    organiserMetric(value: groupRide.checkedInCount, label: "Here", tint: .mlAccent)
                    Divider().overlay(Color.mlHairline)
                    organiserMetric(value: groupRide.goingCount, label: "Riding", tint: .mlSuccess)
                    Divider().overlay(Color.mlHairline)
                    organiserMetric(value: groupRide.maybeCount, label: "Maybe", tint: .mlWarning)
                }

                if groupRide.status == .scheduled {
                    Button {
                        showingAnnouncementComposer = true
                    } label: {
                        Label("Send rider update", systemImage: "megaphone.fill")
                            .font(MLFont.headline)
                            .foregroundStyle(Color.mlAccent)
                            .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                    }
                    .buttonStyle(MLPressableButtonStyle())
                    .background(Color.mlAccent.opacity(0.10), in: Capsule())
                }

                if groupRide.declinedCount > 0 {
                    Text("\(groupRide.declinedCount) declined")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            }
        }
    }

    private func expectedRiderCount(_ groupRide: GroupRide) -> Int {
        let hostAlreadyCounted = groupRide.members.contains {
            $0.isYou && $0.rsvp == .going
        }
        let expected = groupRide.goingCount + (hostAlreadyCounted ? 0 : 1)
        return max(expected, groupRide.checkedInCount)
    }

    private func readinessTitle(_ groupRide: GroupRide) -> String {
        if groupRide.checkedInCount == 0 { return "Waiting for riders" }
        if groupRide.checkedInCount >= expectedRiderCount(groupRide) { return "Everyone is here" }
        return "Riders are arriving"
    }

    private func announcements(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Host Updates")

            ForEach(visibleAnnouncements(groupRide)) { announcement in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "megaphone.fill")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                        .background(Color.mlAccent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(announcement.message)
                            .font(MLFont.body)
                            .foregroundStyle(Color.mlTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(announcement.authorName) · \(announcement.createdAt.formatted(.relative(presentation: .named)))")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextTertiary)
                    }
                }
                .padding(Spacing.md)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.mlAccent.opacity(0.20), lineWidth: Layout.hairline)
                }
            }

            if groupRide.announcements.count > 1 {
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : Motion.spring) {
                        showAllAnnouncements.toggle()
                    }
                } label: {
                    Label(
                        showAllAnnouncements ? "Show latest only" : "Show all updates",
                        systemImage: showAllAnnouncements ? "chevron.up" : "chevron.down"
                    )
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlAccent)
                    .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                }
                .buttonStyle(MLPressableButtonStyle())
            }
        }
    }

    private func visibleAnnouncements(_ groupRide: GroupRide) -> [GroupRideAnnouncement] {
        showAllAnnouncements ? groupRide.announcements : Array(groupRide.announcements.prefix(1))
    }

    private func organiserMetric(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text("\(value)")
                .font(MLFont.title2)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity)
    }

    private func visibleMembers(_ groupRide: GroupRide) -> [GroupRideMember] {
        showAllAttendees ? groupRide.members : Array(groupRide.members.prefix(4))
    }

    private func rsvpTint(_ rsvp: GroupRideRSVP) -> Color {
        switch rsvp {
        case .going: .mlSuccess
        case .maybe: .mlWarning
        case .no: .mlTextTertiary
        }
    }

    private func actions(_ groupRide: GroupRide) -> some View {
        VStack(spacing: Spacing.md) {
            if groupRide.status == .scheduled {
                PrimaryButton(title: "Start Group Route", systemImage: "location.north.line.fill", isLoading: viewModel.isWorking) {
                    pendingStartRide = groupRide
                }
                .disabled(!groupRide.isOwner && groupRide.isFull && groupRide.yourRSVP != .going)
            }

            SecondaryButton(title: groupRide.visibility == .community ? "Share Community Ride" : "Share Invite", systemImage: "square.and.arrow.up") {
                if let inviteURL = groupRide.inviteURL {
                    activityPayload = ActivityPayload(items: [inviteURL])
                }
            }

            if groupRide.isOwner && groupRide.status == .scheduled {
                Menu {
                    Button("Edit Ride", systemImage: "pencil") {
                        showingMeetingEditor = true
                    }
                    Button("Mark Complete", systemImage: "checkmark.circle") {
                        pendingStatus = .completed
                    }
                    Button("Cancel Group Ride", systemImage: "xmark.circle", role: .destructive) {
                        pendingStatus = .cancelled
                    }
                } label: {
                    Label("Manage Group Ride", systemImage: "slider.horizontal.3")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.mlSurfaceElevated, in: Capsule())
                }
                .buttonStyle(MLPressableButtonStyle())
            } else if groupRide.isMember && groupRide.status == .scheduled {
                Button(role: .destructive) {
                    showingLeaveConfirmation = true
                } label: {
                    Label("Leave Group Ride", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .frame(minHeight: 52)
                        .background(Capsule().stroke(Color.mlDanger.opacity(0.4), lineWidth: Layout.hairline))
                }
                .buttonStyle(MLPressableButtonStyle())
                .disabled(viewModel.isWorking)
            }
        }
    }
}

private struct GroupRideStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let groupRide: GroupRide
    let onStart: (Bool) async -> Bool

    @State private var shareLiveLocation = false
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Image(systemName: "person.3.fill")
                        .font(MLFont.displaySmall)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Spacing.xxl, height: Spacing.xxl)
                        .background(Color.mlAccent.opacity(0.12), in: Circle())

                    Text(groupRide.title)
                        .font(MLFont.title2)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("Your ride records normally whether live sharing is on or off.")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Toggle(isOn: $shareLiveLocation) {
                        Label {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Share my live position")
                                    .font(MLFont.bodyEmphasised)
                                    .foregroundStyle(Color.mlTextPrimary)
                                Text("Off by default for every ride")
                                    .font(MLFont.caption)
                                    .foregroundStyle(Color.mlTextSecondary)
                            }
                        } icon: {
                            Image(systemName: shareLiveLocation ? "location.fill" : "location.slash.fill")
                                .foregroundStyle(shareLiveLocation ? Color.mlAccent : Color.mlTextTertiary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .tint(.mlAccent)
                    .onChange(of: shareLiveLocation) { _, _ in Haptics.selection() }

                    if shareLiveLocation {
                        Label(
                            "Only the host and riders marked Riding can see you. Updates expire within two minutes when sharing stops.",
                            systemImage: "hand.raised.fill"
                        )
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(Spacing.md)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(shareLiveLocation ? Color.mlAccent.opacity(0.38) : Color.mlHairline, lineWidth: Layout.hairline)
                }
                .animation(reduceMotion ? nil : Motion.springSnappy, value: shareLiveLocation)

                Spacer(minLength: 0)

                PrimaryButton(
                    title: shareLiveLocation ? "Start & Share" : "Start Ride",
                    systemImage: "location.north.line.fill",
                    isLoading: isStarting
                ) {
                    isStarting = true
                    Task {
                        let started = await onStart(shareLiveLocation)
                        isStarting = false
                        if started { dismiss() }
                    }
                }
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
            .background(Color.mlBackground)
            .navigationTitle("Before You Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isStarting)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { shareLiveLocation = false }
    }
}

private struct GroupRideAnnouncementComposer: View {
    let onSend: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Ride-day update").mlKicker()
                    Text("Tell everyone at once")
                        .font(MLFont.displaySmall)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("Riders will see this in the lobby. Push delivery follows each rider's notification settings.")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Fuel stop changed, running ten minutes late...", text: $message, axis: .vertical)
                    .lineLimit(4...7)
                    .textFieldStyle(MLTextFieldStyle())
                    .onChange(of: message) { _, newValue in
                        if newValue.count > 500 {
                            message = String(newValue.prefix(500))
                        }
                    }

                HStack {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlDanger)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                    Text("\(message.count)/500")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .monospacedDigit()
                }

                PrimaryButton(title: "Send Update", systemImage: "paperplane.fill", isLoading: isSending) {
                    Task { await send() }
                }
                .disabled(cleanMessage.isEmpty || isSending)

                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.lg)
            .mlScreenPadding()
            .background(Color.mlBackground)
            .navigationTitle("Rider Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
            }
            .animation(reduceMotion ? nil : Motion.spring, value: errorMessage)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSending)
    }

    private var cleanMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() async {
        guard !cleanMessage.isEmpty, !isSending else { return }
        isSending = true
        errorMessage = nil
        let sent = await onSend(cleanMessage)
        isSending = false
        if sent {
            Haptics.success()
            dismiss()
        } else {
            Haptics.error()
            errorMessage = "The update wasn't sent. Check your connection and try again."
        }
    }
}

struct GroupRideCreationSheet: View {
    let route: PlannedRoute
    let service: GroupRideServing
    let onCreated: (GroupRide) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var title: String
    @State private var details = ""
    @State private var visibility = GroupRideVisibility.inviteOnly
    @State private var hasMeetTime = true
    @State private var meetTime = Date().addingTimeInterval(86_400)
    @State private var meetPoint = ""
    @State private var hasCapacity = false
    @State private var capacity = 12
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(route: PlannedRoute, service: GroupRideServing, onCreated: @escaping (GroupRide) -> Void) {
        self.route = route
        self.service = service
        self.onCreated = onCreated
        _title = State(initialValue: "\(route.title) Group Ride")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Organise").mlKicker()
                        Text("Create Group Ride")
                            .font(MLFont.display)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text(route.title)
                            .font(MLFont.body)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    .mlStaggeredReveal(index: 0)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Ride name").mlKicker()
                        TextField("Group ride name", text: $title)
                            .textFieldStyle(MLTextFieldStyle())
                        Text("What riders should know").mlKicker()
                            .padding(.top, Spacing.xs)
                        TextField("Pace, fuel stop, what to bring...", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(MLTextFieldStyle())
                    }
                    .mlStaggeredReveal(index: 1)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Who can find it").mlKicker()
                        Picker("Visibility", selection: $visibility) {
                            ForEach(GroupRideVisibility.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(visibility.detail)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card))
                    .mlStaggeredReveal(index: 2)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Toggle("Set meeting time", isOn: $hasMeetTime)
                            .font(MLFont.bodyEmphasised)
                            .tint(.mlAccent)
                        if hasMeetTime {
                            DatePicker("Meet", selection: $meetTime, in: Date()...)
                                .datePickerStyle(.compact)
                                .tint(.mlAccent)
                        }
                        TextField("Meeting point", text: $meetPoint)
                            .textFieldStyle(MLTextFieldStyle())
                        Divider().overlay(Color.mlHairline)
                        Toggle("Limit group size", isOn: $hasCapacity)
                            .font(MLFont.bodyEmphasised)
                            .tint(.mlAccent)
                        if hasCapacity {
                            Stepper(value: $capacity, in: 2...100) {
                                HStack {
                                    Text("Available places")
                                    Spacer()
                                    Text("\(capacity)")
                                        .foregroundStyle(Color.mlAccent)
                                        .monospacedDigit()
                                }
                                .font(MLFont.body)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card))
                    .mlStaggeredReveal(index: 3)
                    .animation(reduceMotion ? nil : Motion.spring, value: hasMeetTime || hasCapacity)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlDanger)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    PrimaryButton(title: "Create & Share", systemImage: "person.3.fill", isLoading: isSaving) {
                        Task { await create() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .mlStaggeredReveal(index: 4)
                }
                .padding(.vertical, Spacing.md)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle("Group Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .animation(reduceMotion ? nil : Motion.spring, value: errorMessage)
        }
        .preferredColorScheme(.dark)
    }

    private func create() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let draft = GroupRideDraft(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                details: details.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                meetTime: hasMeetTime ? meetTime : nil,
                meetPoint: meetPoint.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                visibility: visibility,
                capacity: hasCapacity ? capacity : nil
            )
            let groupRide = try await service.createGroupRide(
                route: route,
                draft: draft
            )
            Haptics.success()
            dismiss()
            onCreated(groupRide)
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }
}

private struct GroupRideMeetingEditor: View {
    let groupRide: GroupRide
    let isSaving: Bool
    let onSave: (GroupRideDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var title: String
    @State private var details: String
    @State private var visibility: GroupRideVisibility
    @State private var hasMeetTime: Bool
    @State private var meetTime: Date
    @State private var meetPoint: String
    @State private var hasCapacity: Bool
    @State private var capacity: Int

    init(groupRide: GroupRide, isSaving: Bool, onSave: @escaping (GroupRideDraft) async -> Void) {
        self.groupRide = groupRide
        self.isSaving = isSaving
        self.onSave = onSave
        _title = State(initialValue: groupRide.title)
        _details = State(initialValue: groupRide.details ?? "")
        _visibility = State(initialValue: groupRide.visibility)
        _hasMeetTime = State(initialValue: groupRide.meetTime != nil)
        _meetTime = State(initialValue: groupRide.meetTime ?? Date().addingTimeInterval(86_400))
        _meetPoint = State(initialValue: groupRide.meetPoint ?? "")
        _hasCapacity = State(initialValue: groupRide.capacity != nil)
        _capacity = State(initialValue: groupRide.capacity ?? 12)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Ride details").mlKicker()
                        TextField("Group ride name", text: $title)
                            .textFieldStyle(MLTextFieldStyle())
                        TextField("What riders should know", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(MLTextFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Visibility").mlKicker()
                        Picker("Visibility", selection: $visibility) {
                            ForEach(GroupRideVisibility.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(visibility.detail)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card))

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Toggle("Set meeting time", isOn: $hasMeetTime)
                            .font(MLFont.bodyEmphasised)
                            .tint(.mlAccent)
                        if hasMeetTime {
                            DatePicker("Meet", selection: $meetTime)
                                .tint(.mlAccent)
                        }
                        TextField("Meeting point", text: $meetPoint)
                            .textFieldStyle(MLTextFieldStyle())
                        Divider().overlay(Color.mlHairline)
                        Toggle("Limit group size", isOn: $hasCapacity)
                            .font(MLFont.bodyEmphasised)
                            .tint(.mlAccent)
                        if hasCapacity {
                            Stepper("\(capacity) places", value: $capacity, in: 2...100)
                                .font(MLFont.body)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card))
                    .animation(reduceMotion ? nil : Motion.spring, value: hasMeetTime || hasCapacity)
                }
                .padding(.vertical, Spacing.md)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle("Edit Group Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSave(GroupRideDraft(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                details: details.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                meetTime: hasMeetTime ? meetTime : nil,
                                meetPoint: meetPoint.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                visibility: visibility,
                                capacity: hasCapacity ? capacity : nil
                            ))
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MLTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(MLFont.body)
            .foregroundStyle(Color.mlTextPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 52)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
