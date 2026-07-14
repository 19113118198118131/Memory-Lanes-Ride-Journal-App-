import SwiftUI

struct RiderCraftRideView: View {
    let analysis: RiderCraftAnalysis
    let onReplay: (Int) -> Void

    @State private var showAllEvents = false

    private var orderedEvents: [RiderCraftEvent] {
        analysis.events.sorted { $0.replayIndex < $1.replayIndex }
    }

    private var visibleEvents: [RiderCraftEvent] {
        showAllEvents ? orderedEvents : Array(orderedEvents.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Safety-first coaching").mlKicker()
                    Text("Rider Craft")
                        .font(MLFont.title2)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                Text("CALIBRATING")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlWarning)
                    .padding(.horizontal, Spacing.xs)
                    .frame(height: 26)
                    .background(Color.mlWarning.opacity(0.12), in: Capsule())
            }

            headline

            if let line = analysis.calibrationDebriefLine {
                Label(line, systemImage: "scope")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.md)
                    .background(Color.mlAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }

            detectorGrid

            if !orderedEvents.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: "Review on Replay")
                    ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { index, event in
                        eventRow(event)
                            .mlStaggeredReveal(index: index)
                    }
                    if orderedEvents.count > 4 {
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.spring) { showAllEvents.toggle() }
                        } label: {
                            Label(
                                showAllEvents ? "Show key events" : "Review all \(orderedEvents.count) detections",
                                systemImage: showAllEvents ? "chevron.up" : "chevron.down"
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

            Label(
                "These are GPS-derived prompts for reflection, not proof of rider error. Road geometry and one-second sampling can change what the detector sees.",
                systemImage: "info.circle"
            )
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(analysis.eventsPerCorner.map { String(format: "%.2f", $0) } ?? "--")
                    .font(MLFont.display)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("DETECTIONS / CORNER").mlKicker()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text("\(analysis.detectedCornerCount)")
                    .font(MLFont.mono)
                    .foregroundStyle(Color.mlAccent)
                Text("CORNERS SEEN").mlKicker()
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private var detectorGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
            spacing: Spacing.sm
        ) {
            ForEach(RiderCraftEvent.Kind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(analysis.categoryCounts[kind, default: 0])")
                        .font(MLFont.mono)
                        .foregroundStyle(analysis.categoryCounts[kind, default: 0] > 0 ? Color.mlWarning : Color.mlTextPrimary)
                    Text(kind.title)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(2)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
        }
    }

    private func eventRow(_ event: RiderCraftEvent) -> some View {
        Button {
            Haptics.selection()
            onReplay(event.replayIndex)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol(event.kind))
                    .foregroundStyle(Color.mlWarning)
                    .frame(width: 40, height: 40)
                    .background(Color.mlWarning.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(event.kind.title)
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("Detected corner \(event.cornerIndex)")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                Spacer()
                Label("Replay", systemImage: "play.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlAccent)
            }
            .padding(Spacing.sm)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle(scale: 0.98))
    }

    private func symbol(_ kind: RiderCraftEvent.Kind) -> String {
        switch kind {
        case .brakeAfterTurnIn: "hand.raised.fill"
        case .flatExit: "arrow.up.forward"
        case .earlyApex: "arrow.turn.up.right"
        case .brakedDeep: "scope"
        }
    }
}

struct RiderCraftProgressView: View {
    let progress: RiderCraftProgress

    @State private var showBadges = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Rider Craft")
            Text("Progress against your own recent riding. Nothing here rewards speed, lean, distance, or frequency.")
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if progress.eligibleRideCount == 0 {
                Label("Open an analysed ride to begin your Rider Craft history.", systemImage: "scope")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            } else {
                trendCard
                if let focus = progress.focus { focusCard(focus) }
                badges
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(progress.currentRate.map { String(format: "%.2f", $0) } ?? "--")
                        .font(MLFont.displaySmall)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("DETECTIONS / CORNER").mlKicker()
                }
                Spacer()
                if let delta = progress.rateDelta {
                    Text(deltaText(delta))
                        .font(MLFont.caption)
                        .foregroundStyle(delta <= 0 ? Color.mlSuccess : Color.mlTextSecondary)
                }
            }

            HStack(alignment: .bottom, spacing: Spacing.xs) {
                let maximum = max(progress.trend.map(\.rate).max() ?? 1, 0.1)
                ForEach(Array(progress.trend.enumerated()), id: \.element.id) { index, point in
                    Capsule()
                        .fill(index == progress.trend.count - 1 ? Color.mlAccent : Color.mlTextTertiary.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(8, CGFloat(point.rate / maximum) * 72))
                        .accessibilityLabel("\(point.date.formatted(date: .abbreviated, time: .omitted)): \(String(format: "%.2f", point.rate)) detections per corner")
                }
            }
            .frame(height: 78, alignment: .bottom)

            Text("Lower means fewer of the four supported GPS patterns. One ride is never a verdict.")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.mlHairline, lineWidth: Layout.hairline))
    }

    private func focusCard(_ focus: RiderCraftFocus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Current Focus", systemImage: focus.kind.symbol)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlAccent)
                Spacer()
                Text("ONE SKILL").mlKicker()
            }
            Text(focus.title)
                .font(MLFont.title2)
                .foregroundStyle(Color.mlTextPrimary)
            Text(focus.evidence)
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
            Divider().overlay(Color.mlHairline)
            Text(focus.drill)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
            Label(focus.target, systemImage: "target")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlInfo)
        }
        .padding(Spacing.md)
        .background(Color.mlAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.mlAccent.opacity(0.28), lineWidth: Layout.hairline))
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                Haptics.selection()
                withAnimation(Motion.spring) { showBadges.toggle() }
            } label: {
                HStack {
                    Text("Road-craft markers")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                    Spacer()
                    Text("\(progress.badges.filter(\.isEarned).count) / \(progress.badges.count)")
                        .font(MLFont.monoSmall)
                        .foregroundStyle(Color.mlTextSecondary)
                    Image(systemName: showBadges ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.mlAccent)
                }
                .frame(minHeight: Layout.minTouchTarget)
            }
            .buttonStyle(MLPressableButtonStyle(scale: 0.98))

            if showBadges {
                ForEach(Array(progress.badges.enumerated()), id: \.element.id) { index, badge in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: badge.symbol)
                            .foregroundStyle(badge.isEarned ? Color.mlSuccess : Color.mlTextTertiary)
                            .frame(width: 40, height: 40)
                            .background(
                                (badge.isEarned ? Color.mlSuccess : Color.mlTextTertiary).opacity(0.1),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(badge.title)
                                .font(MLFont.bodyEmphasised)
                                .foregroundStyle(Color.mlTextPrimary)
                            Text(badge.detail)
                                .font(MLFont.caption)
                                .foregroundStyle(Color.mlTextSecondary)
                        }
                        Spacer()
                        Text(badge.isEarned ? "Earned" : "Building")
                            .mlKicker()
                    }
                    .padding(.vertical, Spacing.xs)
                    .mlStaggeredReveal(index: index)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.mlHairline, lineWidth: Layout.hairline))
    }

    private func deltaText(_ delta: Double) -> String {
        if abs(delta) < 0.01 { return "In line with recent rides" }
        return String(format: "%+.2f vs recent", delta)
    }
}
