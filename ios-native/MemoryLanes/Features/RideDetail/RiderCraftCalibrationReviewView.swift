import SwiftUI

struct RiderCraftCalibrationReviewView: View {
    private enum ReviewSet: String, CaseIterable, Identifiable {
        case candidates = "Flagged"
        case controls = "Checks"

        var id: Self { self }
    }

    @Bindable var viewModel: RideDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reviewSet: ReviewSet = .candidates
    @State private var selectedTargetID: String?
    @State private var selectedControlKind: RiderCraftEvent.Kind?
    @State private var activityPayload: ActivityPayload?
    @State private var isGuideExpanded = true
    @State private var confirmingReset = false
    @State private var toast: Toast?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summary
                    calibrationGuide
                    Picker("Review set", selection: $reviewSet) {
                        ForEach(ReviewSet.allCases) { set in
                            Text(set.rawValue).tag(set)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let target = selectedTarget {
                        replayMap(target)
                        targetNavigator(target)
                        targetEvidence(target)
                        decisionControls(target)
                    } else {
                        EmptyState(
                            systemImage: "checkmark.seal",
                            title: reviewSet == .candidates ? "No flagged moments" : "No check moments",
                            message: "There is nothing to review in this part of the ride."
                        )
                    }

                    if let message = viewModel.calibrationReviewErrorMessage {
                        Text(message)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlDanger)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card))
                    }
                }
                .padding(.vertical, Spacing.md)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle("Calibrate Rider Craft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportReviews()
                    } label: {
                        if viewModel.isExportingCalibrationReviews {
                            ProgressView().tint(.mlAccent)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(viewModel.isExportingCalibrationReviews || viewModel.calibrationReviewedCount == 0)
                    .accessibilityLabel("Export calibration reviews")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectFirstTarget(preferUnreviewed: true)
            syncSelectedControlKind()
        }
        .onChange(of: reviewSet) { _, _ in selectFirstTarget(preferUnreviewed: true) }
        .onChange(of: selectedTargetID) { _, _ in
            if let selectedTarget {
                viewModel.focusCalibrationTarget(selectedTarget)
                syncSelectedControlKind()
            }
        }
        .sheet(item: $activityPayload) { payload in
            ActivityView(items: payload.items)
        }
        .confirmationDialog(
            "Reset calibration for this ride?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset This Ride", role: .destructive) { resetRideCalibration() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears every answer for this ride only. Your ride, analysis, and other calibrated rides will not be changed.")
        }
        .mlToast($toast)
    }

    private var filteredTargets: [RiderCraftCalibrationReviewTarget] {
        viewModel.calibrationReviewTargets.filter {
            reviewSet == .controls ? $0.isControl : !$0.isControl
        }
    }

    private var selectedTarget: RiderCraftCalibrationReviewTarget? {
        filteredTargets.first { $0.id == selectedTargetID } ?? filteredTargets.first
    }

    private var summary: some View {
        let reviewSummary = viewModel.calibrationReviewSummary
        let candidateMatches = reviewSummary.detectors.map(\.candidateMatches).reduce(0, +)
        let candidateMismatches = reviewSummary.detectors.map(\.candidateMismatches).reduce(0, +)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Optional · about one minute").mlKicker()
            Text("Help Rider Craft understand this ride")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlTextPrimary)
            Text("GPS can confuse traffic, road shape, or a signal jump with riding technique. A few quick answers show where the app read your trace correctly and where it did not.")
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(
                value: Double(viewModel.calibrationReviewedCount),
                total: Double(max(viewModel.calibrationReviewTargets.count, 1))
            )
            .tint(.mlAccent)

            Text("\(viewModel.calibrationReviewedCount) of \(viewModel.calibrationReviewTargets.count) moments checked")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)

            Divider().overlay(Color.mlHairline)

            HStack(spacing: Spacing.sm) {
                summaryMetric("Looks right", value: candidateMatches, tint: .mlSuccess)
                summaryMetric("Not right", value: candidateMismatches, tint: .mlDanger)
                summaryMetric("Missed", value: reviewSummary.controlMisses, tint: .mlInfo)
            }

            if viewModel.calibrationReviewedCount > 0 {
                Button {
                    confirmingReset = true
                } label: {
                    Label("Reset calibration for this ride", systemImage: "arrow.counterclockwise")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlDanger)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                }
                .buttonStyle(MLPressableButtonStyle())
                .disabled(viewModel.isResettingCalibrationReviews)
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private var calibrationGuide: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : Motion.spring) { isGuideExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(Color.mlAccent)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("How calibration helps")
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text("What to look for and what your answers do")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Spacer()
                    Image(systemName: isGuideExpanded ? "chevron.up" : "chevron.down")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                .frame(minHeight: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)

            if isGuideExpanded {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    guideStep(1, "Look at the corner", "The map jumps to one moment. Use the road shape and replay point as a reminder, not as a test of your riding.")
                    guideStep(2, "Give the simple answer", "Choose Looks right when the highlighted pattern seems visible, Not right when it does not, or Not sure when the GPS is unclear.")
                    guideStep(3, "Check both lists", "Flagged shows what Rider Craft noticed. Checks samples ordinary corners so you can tell us if it missed something obvious.")

                    Label(
                        "Your answers stay on this phone until exported. They help us tune future detection so coaching becomes more accurate and less noisy; they do not change this ride's score.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Tip: tap your selected answer again to uncheck it.")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlAccent)
                }
                .padding(.top, Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlAccent.opacity(0.35), lineWidth: Layout.hairline)
        )
    }

    private func guideStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(number)")
                .font(MLFont.monoSmall)
                .foregroundStyle(Color.mlOnAccent)
                .frame(width: 28, height: 28)
                .background(Color.mlAccent, in: Circle())
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(detail)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func replayMap(_ target: RiderCraftCalibrationReviewTarget) -> some View {
        MLMapView(
            route: viewModel.routeForMomentPinning,
            replayIndex: target.replayIndex,
            replayCoordinate: viewModel.currentReplayCoordinate,
            guideRoute: viewModel.plannedGuideRoute
        )
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func targetNavigator(_ target: RiderCraftCalibrationReviewTarget) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                moveSelection(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(MLPressableButtonStyle())
            .disabled(selectedIndex == 0)
            .accessibilityLabel("Previous calibration target")

            VStack(spacing: Spacing.xxs) {
                Text("Corner \(target.cornerIndex)")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("\(selectedIndex + 1) of \(filteredTargets.count) in this set")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                moveSelection(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(MLPressableButtonStyle())
            .disabled(selectedIndex >= filteredTargets.count - 1)
            .accessibilityLabel("Next calibration target")
        }
    }

    private func targetEvidence(_ target: RiderCraftCalibrationReviewTarget) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(target.isControl ? "Routine corner check" : "Rider Craft highlighted").mlKicker()
                    Text(target.candidateKind?.title ?? "No pattern was highlighted")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                if let decision = viewModel.calibrationDecision(for: target) {
                    Label(decisionTitle(decision), systemImage: decisionSymbol(decision))
                        .font(MLFont.caption)
                        .foregroundStyle(decisionTint(decision))
                }
            }

            if let evidence = evidenceText(target) {
                Text(evidence)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            Text(target.isControl
                 ? "Look for an obvious pattern Rider Craft may have missed. Most check moments should simply be No miss."
                 : "Look at the road shape and replay point. Does the highlighted pattern seem consistent with this moment?")
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func decisionControls(_ target: RiderCraftCalibrationReviewTarget) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What does the replay show?").mlKicker()
            if target.isControl {
                HStack {
                    Text("If something was missed")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                    Spacer()
                    Picker("Missed detector", selection: $selectedControlKind) {
                        Text("Choose the pattern").tag(RiderCraftEvent.Kind?.none)
                        ForEach(RiderCraftEvent.Kind.calibrationControlKinds, id: \.self) { kind in
                            Text(kind.title).tag(RiderCraftEvent.Kind?.some(kind))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.mlAccent)
                }
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 44)
                .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.button))
            }
            HStack(spacing: Spacing.sm) {
                decisionButton(
                    target.isControl ? "No miss" : "Looks right",
                    symbol: "checkmark",
                    decision: .match,
                    tint: .mlSuccess,
                    target: target
                )
                decisionButton(
                    target.isControl ? "Missed one" : "Not right",
                    symbol: "xmark",
                    decision: .mismatch,
                    tint: .mlDanger,
                    target: target
                )
                decisionButton(
                    "Unsure",
                    symbol: "questionmark",
                    decision: .unsure,
                    tint: .mlInfo,
                    target: target
                )
            }
        }
    }

    private func decisionButton(
        _ title: String,
        symbol: String,
        decision: RiderCraftCalibrationReview.Decision,
        tint: Color,
        target: RiderCraftCalibrationReviewTarget
    ) -> some View {
        let isSelected = viewModel.calibrationDecision(for: target) == decision
        return Button {
            Task {
                let saved: Bool
                if isSelected {
                    saved = await viewModel.clearCalibrationDecision(for: target)
                } else {
                    saved = await viewModel.saveCalibrationDecision(
                        decision,
                        for: target,
                        suspectedKind: target.isControl ? selectedControlKind : nil
                    )
                }
                if saved {
                    Haptics.selection()
                    if !isSelected { selectNextUnreviewed(after: target) }
                } else {
                    Haptics.error()
                }
            }
        } label: {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: symbol)
                    .font(MLFont.callout)
                Text(title)
                    .font(MLFont.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Color.mlOnAccent : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                isSelected ? tint : Color.mlSurfaceElevated,
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(tint.opacity(isSelected ? 0 : 0.45), lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle())
        .disabled(target.isControl && decision == .mismatch && selectedControlKind == nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double tap to clear this answer" : "Double tap to choose this answer")
    }

    private var selectedIndex: Int {
        guard let selectedTargetID,
              let index = filteredTargets.firstIndex(where: { $0.id == selectedTargetID }) else { return 0 }
        return index
    }

    private func moveSelection(by offset: Int) {
        guard !filteredTargets.isEmpty else { return }
        let index = min(max(selectedIndex + offset, 0), filteredTargets.count - 1)
        selectedTargetID = filteredTargets[index].id
    }

    private func selectFirstTarget(preferUnreviewed: Bool) {
        let target = preferUnreviewed
            ? filteredTargets.first(where: { viewModel.calibrationDecision(for: $0) == nil }) ?? filteredTargets.first
            : filteredTargets.first
        selectedTargetID = target?.id
        if let target { viewModel.focusCalibrationTarget(target) }
    }

    private func selectNextUnreviewed(after target: RiderCraftCalibrationReviewTarget) {
        guard let current = filteredTargets.firstIndex(of: target) else { return }
        let ordered = Array(filteredTargets.dropFirst(current + 1)) + Array(filteredTargets.prefix(current))
        if let next = ordered.first(where: { viewModel.calibrationDecision(for: $0) == nil }) {
            selectedTargetID = next.id
        }
    }

    private func syncSelectedControlKind() {
        guard let selectedTarget else {
            selectedControlKind = nil
            return
        }
        selectedControlKind = viewModel.calibrationSuspectedKind(for: selectedTarget)
    }

    private func summaryMetric(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("\(value)")
                .font(MLFont.mono)
                .foregroundStyle(tint)
            Text(title)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func evidenceText(_ target: RiderCraftCalibrationReviewTarget) -> String? {
        guard let kind = target.candidateKind,
              let value = target.measuredValue,
              let threshold = target.threshold else { return nil }
        switch kind {
        case .brakeAfterTurnIn:
            return "Braking began at \(Int((value * 100).rounded()))% of the detected corner."
        case .flatExit:
            return String(format: "Exit drive %.2f m/s² · candidate below %.2f", value, threshold)
        case .earlyApex:
            return "Apex proxy at \(Int((value * 100).rounded()))% · candidate at or before \(Int((threshold * 100).rounded()))%"
        case .brakedDeep:
            return "Braking depth \(Int((value * 100).rounded()))% · candidate above \(Int((threshold * 100).rounded()))%"
        }
    }

    private func decisionTitle(_ decision: RiderCraftCalibrationReview.Decision) -> String {
        switch decision {
        case .match: "Match"
        case .mismatch: "Mismatch"
        case .unsure: "Unsure"
        }
    }

    private func decisionSymbol(_ decision: RiderCraftCalibrationReview.Decision) -> String {
        switch decision {
        case .match: "checkmark.circle.fill"
        case .mismatch: "xmark.circle.fill"
        case .unsure: "questionmark.circle.fill"
        }
    }

    private func decisionTint(_ decision: RiderCraftCalibrationReview.Decision) -> Color {
        switch decision {
        case .match: .mlSuccess
        case .mismatch: .mlDanger
        case .unsure: .mlInfo
        }
    }

    private func exportReviews() {
        Task {
            do {
                activityPayload = ActivityPayload(items: [try await viewModel.exportCalibrationReviews()])
            } catch {
                Haptics.error()
            }
        }
    }

    private func resetRideCalibration() {
        Task {
            if await viewModel.resetCalibrationReviews() {
                Haptics.success()
                selectFirstTarget(preferUnreviewed: false)
                toast = .success("Calibration reset for this ride")
            } else {
                Haptics.error()
                toast = .error("Calibration could not be reset")
            }
        }
    }
}
