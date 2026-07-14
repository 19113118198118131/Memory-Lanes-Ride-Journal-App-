import SwiftUI

struct GroupRideLobbyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: GroupRideViewModel
    @State private var activityPayload: ActivityPayload?
    @State private var showingMeetingEditor = false
    @State private var showingEndConfirmation = false
    @State private var showAllAttendees = false

    let onStartRoute: (PlannedRoute) -> Void
    let onEnded: () -> Void

    init(
        viewModel: GroupRideViewModel,
        onStartRoute: @escaping (PlannedRoute) -> Void = { _ in },
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
        .task { await viewModel.load() }
        .sheet(item: $activityPayload) { payload in
            ActivityView(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingMeetingEditor) {
            if let groupRide = viewModel.groupRide {
                GroupRideMeetingEditor(groupRide: groupRide, isSaving: viewModel.isWorking) { meetTime, meetPoint in
                    let saved = await viewModel.updateMeeting(meetTime: meetTime, meetPoint: meetPoint)
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
        .confirmationDialog(
            "End this group ride?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Group Ride", role: .destructive) {
                Task {
                    if await viewModel.endRide() {
                        Haptics.success()
                        onEnded()
                    } else {
                        Haptics.error()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The invite will stop working and this ride will leave every member's group-ride list.")
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
                    .init(value: groupRide.elevationM.map { String(format: "%.0f", $0) } ?? "--", unit: "m", label: "Ascent"),
                    .init(value: "\(groupRide.members.filter { $0.rsvp != .no }.count)", unit: "", label: "Riders")
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
                rsvpCard(groupRide)
                    .mlStaggeredReveal(index: 4)
                attendees(groupRide)
                    .mlStaggeredReveal(index: 5)
                actions(groupRide)
                    .mlStaggeredReveal(index: 6)

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
            Text(groupRide.title)
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text(hostLine(groupRide))
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
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

    private func rsvpCard(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your RSVP")
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
        .animation(reduceMotion ? nil : Motion.springSnappy, value: viewModel.pendingRSVP)
    }

    private func attendees(_ groupRide: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Who's Coming")
            if groupRide.members.isEmpty {
                Text("No responses yet")
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
                        Label(member.rsvp.title, systemImage: member.rsvp.symbol)
                            .font(MLFont.caption)
                            .foregroundStyle(rsvpTint(member.rsvp))
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
            PrimaryButton(title: "Start Group Route", systemImage: "location.north.line.fill", isLoading: viewModel.isWorking) {
                Task {
                    if await viewModel.setRSVP(.going) {
                        onStartRoute(groupRide.plannedRoute)
                    } else {
                        Haptics.error()
                    }
                }
            }

            SecondaryButton(title: "Share Invite", systemImage: "square.and.arrow.up") {
                if let inviteURL = groupRide.inviteURL {
                    activityPayload = ActivityPayload(items: [inviteURL])
                }
            }

            if groupRide.isOwner {
                Button(role: .destructive) {
                    showingEndConfirmation = true
                } label: {
                    Label("End Group Ride", systemImage: "xmark.circle")
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

struct GroupRideCreationSheet: View {
    let route: PlannedRoute
    let service: GroupRideServing
    let onCreated: (GroupRide) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var title: String
    @State private var hasMeetTime = true
    @State private var meetTime = Date().addingTimeInterval(86_400)
    @State private var meetPoint = ""
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
                    }
                    .mlStaggeredReveal(index: 1)

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
                    }
                    .padding(Spacing.md)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card))
                    .mlStaggeredReveal(index: 2)
                    .animation(reduceMotion ? nil : Motion.spring, value: hasMeetTime)

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
                    .mlStaggeredReveal(index: 3)
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
            let groupRide = try await service.createGroupRide(
                route: route,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                meetTime: hasMeetTime ? meetTime : nil,
                meetPoint: meetPoint.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
    let onSave: (Date?, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasMeetTime: Bool
    @State private var meetTime: Date
    @State private var meetPoint: String

    init(groupRide: GroupRide, isSaving: Bool, onSave: @escaping (Date?, String?) async -> Void) {
        self.groupRide = groupRide
        self.isSaving = isSaving
        self.onSave = onSave
        _hasMeetTime = State(initialValue: groupRide.meetTime != nil)
        _meetTime = State(initialValue: groupRide.meetTime ?? Date().addingTimeInterval(86_400))
        _meetPoint = State(initialValue: groupRide.meetPoint ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Set meeting time", isOn: $hasMeetTime)
                if hasMeetTime {
                    DatePicker("Meet", selection: $meetTime)
                }
                TextField("Meeting point", text: $meetPoint)
            }
            .scrollContentBackground(.hidden)
            .background(Color.mlBackground)
            .navigationTitle("Meeting Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSave(
                                hasMeetTime ? meetTime : nil,
                                meetPoint.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            )
                        }
                    }
                    .disabled(isSaving)
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
