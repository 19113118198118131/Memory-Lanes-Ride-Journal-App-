import SwiftUI
import MapKit

struct LimitPointPlannerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let route: [Coordinate]

    @State private var referenceSpeedKmh = 70
    @State private var analysis: LimitPointAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Pre-ride view study").mlKicker()
                    Text("Limit Point")
                        .font(MLFont.title2)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .foregroundStyle(Color.mlWarning)
            }

            Text("Explore where road geometry may shorten the view around a bend. The selected speed is a comparison setting, never a target.")
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            MLSegmentedControl(
                items: [50, 70, 90, 110],
                title: { "\($0)" },
                selection: $referenceSpeedKmh
            )

            Text("REFERENCE KM/H").mlKicker()

            Text("RESEARCH MODEL V\(LimitPointAnalyzer.modelVersion) · LOW CONFIDENCE")
                .mlKicker()

            if let analysis {
                LimitPointAnalysisContent(analysis: analysis)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                SkeletonBar(height: 300, radius: Radius.card).mlShimmer()
            }

            modelNote
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
        .task(id: referenceSpeedKmh) {
            let route = route
            let speed = Double(referenceSpeedKmh)
            let result = await Task.detached {
                LimitPointAnalyzer().analyze(route: route, referenceSpeedKmh: speed)
            }.value
            withAnimation(reduceMotion ? nil : Motion.spring) { analysis = result }
        }
    }

    private var modelNote: some View {
        Label(
            "Geometry estimate only. It assumes a fixed 5 m obstruction offset and cannot see traffic, fog, hedge growth, surface hazards, or low sun.",
            systemImage: "info.circle"
        )
        .font(MLFont.caption)
        .foregroundStyle(Color.mlTextTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LimitPointRideView: View {
    let analysis: LimitPointAnalysis
    let onReplay: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Post-ride reflection").mlKicker()
                Text("Limit Point Review")
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("Recorded entry speed compared with a geometry-only sight-distance estimate.")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            LimitPointAnalysisContent(analysis: analysis, onReplay: onReplay)

            Label(
                analysis.wetModel
                    ? "Wet stopping model used from recorded weather. Visibility and grip still vary moment to moment."
                    : "Dry stopping model used. Silence or a positive margin never means a bend was clear.",
                systemImage: analysis.wetModel ? "cloud.rain.fill" : "info.circle"
            )
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LimitPointAnalysisContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let analysis: LimitPointAnalysis
    var onReplay: ((Int) -> Void)? = nil

    @State private var showAll = false
    @State private var selectedCornerID: Int?

    private var orderedCorners: [LimitPointCorner] {
        analysis.corners.sorted { $0.marginMeters < $1.marginMeters }
    }

    private var visibleCorners: [LimitPointCorner] {
        showAll ? orderedCorners : Array(orderedCorners.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            LimitPointMap(analysis: analysis, selectedCornerID: selectedCornerID)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))

            summary
            legend

            if analysis.corners.isEmpty {
                Label("No sustained bends were detected in this route geometry.", systemImage: "road.lanes")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(visibleCorners.enumerated()), id: \.element.id) { offset, corner in
                        cornerRow(corner)
                            .mlStaggeredReveal(index: offset)
                    }
                }

                if analysis.corners.count > 3 {
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : Motion.spring) { showAll.toggle() }
                    } label: {
                        Label(
                            showAll ? "Show key bends" : "Review all \(analysis.corners.count) bends",
                            systemImage: showAll ? "chevron.up" : "chevron.down"
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

    private var summary: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.sm) { summaryMetrics }
            } else {
                HStack(spacing: Spacing.sm) { summaryMetrics }
            }
        }
    }

    private func limitMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(MLFont.mono)
                .foregroundStyle(Color.mlTextPrimary)
            Text(label).mlKicker()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }

    private var legend: some View {
        HStack(spacing: Spacing.md) {
            legendItem("No model deficit", color: .mlAccent)
            legendItem("Thin", color: .mlWarning)
            legendItem("Deficit", color: .mlDanger)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        Label {
            Text(title)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
        } icon: {
            Circle().fill(color).frame(width: 8, height: 8)
        }
    }

    private func cornerRow(_ corner: LimitPointCorner) -> some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Motion.spring) { selectedCornerID = corner.id }
            onReplay?(corner.replayIndex)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: corner.direction == .left ? "arrow.turn.up.left" : "arrow.turn.up.right")
                    .foregroundStyle(tint(corner.severity))
                    .frame(width: 40, height: 40)
                    .background(tint(corner.severity).opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Bend \(corner.index) · \(corner.direction.rawValue)")
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("r≈\(Int(corner.radiusMeters.rounded())) m · view \(Int(corner.sightDistanceMeters.rounded())) m · stop \(Int(corner.stoppingDistanceMeters.rounded())) m")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Spacing.xs)
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(String(format: "%+.0f m", corner.marginMeters))
                        .font(MLFont.monoSmall)
                        .foregroundStyle(tint(corner.severity))
                    Text(onReplay == nil ? "Inspect" : "Replay").mlKicker()
                }
            }
            .padding(Spacing.sm)
            .background(
                selectedCornerID == corner.id ? Color.mlSurfaceElevated : Color.mlBackground.opacity(0.45),
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(selectedCornerID == corner.id ? tint(corner.severity).opacity(0.5) : Color.mlHairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle(scale: 0.98))
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        limitMetric(value: "\(analysis.corners.count)", label: "Bends")
        limitMetric(value: "\(analysis.beyondViewCount)", label: "Below zero")
        limitMetric(
            value: analysis.worstCorner.map { String(format: "%.0f m", $0.marginMeters) } ?? "--",
            label: "Thinnest"
        )
    }

    private func tint(_ severity: LimitPointCorner.Severity) -> Color {
        switch severity {
        case .room: .mlAccent
        case .thin: .mlWarning
        case .beyondView, .severe: .mlDanger
        }
    }
}

private struct LimitPointMap: View {
    let analysis: LimitPointAnalysis
    let selectedCornerID: Int?

    var body: some View {
        Map(initialPosition: .region(RouteGeometry.region(for: analysis.route, paddingFactor: 1.35)), interactionModes: [.pan, .zoom]) {
            if analysis.route.count > 1 {
                MapPolyline(coordinates: analysis.route.clCoordinates)
                    .stroke(Color.mlTextTertiary.opacity(0.42), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(analysis.corners) { corner in
                let segment = routeSegment(for: corner)
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.clCoordinates)
                        .stroke(
                            tint(corner.severity).opacity(selectedCornerID == nil || selectedCornerID == corner.id ? 1 : 0.35),
                            style: StrokeStyle(lineWidth: selectedCornerID == corner.id ? 8 : 6, lineCap: .round, lineJoin: .round)
                        )
                }
                if selectedCornerID == corner.id {
                    Annotation("Bend \(corner.index)", coordinate: corner.coordinate.clCoordinate) {
                        Circle()
                            .fill(tint(corner.severity))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .accessibilityLabel("Limit Point route map")
    }

    private func routeSegment(for corner: LimitPointCorner) -> [Coordinate] {
        guard analysis.route.indices.contains(corner.startIndex),
              analysis.route.indices.contains(corner.endIndex),
              corner.startIndex <= corner.endIndex else { return [] }
        return Array(analysis.route[corner.startIndex...corner.endIndex])
    }

    private func tint(_ severity: LimitPointCorner.Severity) -> Color {
        switch severity {
        case .room: .mlAccent
        case .thin: .mlWarning
        case .beyondView, .severe: .mlDanger
        }
    }
}
