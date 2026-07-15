import Charts
import SwiftUI

struct RideAnalyticsView: View {
    let analytics: RideAnalytics
    let replayPoints: [ReplayPoint]
    let coachScores: [RideCoachScore]
    let debrief: String?
    let coachTrend: String?
    let onSelectReplayIndex: (Int) -> Void
    @AppStorage("analytics.showsAxesAndGrid") private var showsAxesAndGrid = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            approximationLabel
            RideInsightOverview(insights: analytics.insights)
            AnalyticsReadingGuide()
            AnalyticsDisplayOptions(showsAxesAndGrid: $showsAxesAndGrid)
            RideProfileChart(
                points: replayPoints,
                showsAxesAndGrid: showsAxesAndGrid,
                onSelectReplayIndex: onSelectReplayIndex
            )
            CornerRadiusChart(
                points: analytics.cornerPoints,
                showsAxesAndGrid: showsAxesAndGrid,
                onSelectReplayIndex: onSelectReplayIndex
            )
            inputSummary
            InputProfileChart(
                analytics: analytics,
                showsAxesAndGrid: showsAxesAndGrid,
                onSelectReplayIndex: onSelectReplayIndex
            )
            GripUsageChart(points: analytics.gripUsage, showsAxesAndGrid: showsAxesAndGrid)
            RideCoachTechniqueView(
                scores: coachScores,
                debrief: debrief,
                trend: coachTrend,
                showsAxesAndGrid: showsAxesAndGrid
            )
            RideCompositionView(slices: analytics.composition)
        }
    }

    private var approximationLabel: some View {
        Label("GPS-derived estimates, for reflection rather than telemetry", systemImage: "waveform.path")
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
    }

    private var inputSummary: some View {
        HStack(spacing: 0) {
            analyticsMetric("Braking", "\(analytics.brakingZones.count)", "zones")
            analyticsMetric(
                "Hardest",
                analytics.hardestBrakingG.map { String(format: "%.2f", $0) } ?? "--",
                "g"
            )
            analyticsMetric("Feel", analytics.brakingFeelText, "")
        }
        .padding(.vertical, Spacing.sm)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func analyticsMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(label).mlKicker()
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(value.count > 8 ? MLFont.headline : MLFont.displaySmall)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

}

private struct AnalyticsDisplayOptions: View {
    @Binding var showsAxesAndGrid: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(Color.mlAccent)
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(Color.mlAccent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Axes & grid")
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("Show scales and reference guides")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }
            Spacer()
            Toggle("Axes & grid", isOn: $showsAxesAndGrid)
                .labelsHidden()
                .tint(Color.mlAccent)
                .onChange(of: showsAxesAndGrid) { _, _ in Haptics.selection() }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }
}

private struct RideInsightOverview: View {
    let insights: [RideAnalyticsInsight]
    @State private var showsAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleInsights: [RideAnalyticsInsight] {
        showsAll ? insights : Array(insights.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                SectionHeader(title: "Ride Insights")
                Spacer()
                Text("GPS ESTIMATE").mlKicker()
            }

            if insights.isEmpty {
                Text("This ride does not yet have enough clean data for a plain-English insight.")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
            } else {
                ForEach(visibleInsights) { insight in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label(title(insight.kind), systemImage: symbol(insight.kind))
                            .font(MLFont.headline)
                            .foregroundStyle(Color.mlAccent)
                        Text(insight.summary)
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text(insight.detail)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if insights.count > 1 {
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : Motion.spring) { showsAll.toggle() }
                    } label: {
                        Label(
                            showsAll ? "Show key insight" : "Show all \(insights.count) insights",
                            systemImage: showsAll ? "chevron.up" : "chevron.down"
                        )
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlAccent)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                    }
                    .buttonStyle(MLPressableButtonStyle())
                }
            }
        }
        .analyticsCard()
    }

    private func title(_ kind: RideAnalyticsInsight.Kind) -> String {
        switch kind {
        case .grip: "Riding Signature"
        case .corners: "Corner Rhythm"
        case .elevation: "Road Shape"
        case .inputs: "Brake & Throttle"
        }
    }

    private func symbol(_ kind: RideAnalyticsInsight.Kind) -> String {
        switch kind {
        case .grip: "circle.hexagongrid.fill"
        case .corners: "point.topleft.down.to.point.bottomright.curvepath"
        case .elevation: "mountain.2.fill"
        case .inputs: "gauge.with.dots.needle.67percent"
        }
    }
}

private struct AnalyticsReadingGuide: View {
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : Motion.spring) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(Color.mlAccent)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("How to read ride analytics")
                            .font(MLFont.bodyEmphasised)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text("A short guide to every visual")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                .frame(minHeight: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    guideRow("Elevation & speed", "Read the road shape and pace together. Dips can be corners, climbs, junctions, stops, or traffic, so use the map before drawing a conclusion.")
                    guideRow("Corner radius", "Each dot is a detected bend. Left is tighter, right is more open. Vertical spread shows how differently similar-radius bends were approached. Dashed curves are references, never targets.")
                    guideRow("Acceleration", "Below zero is deceleration; above zero is drive. Red and green bands show detected braking and drive zones. Smooth alternation reveals rhythm; spikes may be abrupt input or GPS noise.")
                    guideRow("Grip signature", "Left and right are cornering, down is braking, up is drive. The cloud is a riding signature, not a score and not something to maximise.")
                    guideRow("Ride Coach", "The polygon shows balance across five GPS-supported technique estimates. Use the captions and replay evidence; one ride is never a verdict.")
                }
                .padding(.top, Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func guideRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(MLFont.headline)
                .foregroundStyle(Color.mlTextPrimary)
            Text(detail)
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RideProfileChart: View {
    enum Mode: String, CaseIterable, Hashable {
        case both = "Both"
        case elevation = "Elevation"
        case speed = "Speed"
    }

    let points: [ReplayPoint]
    let showsAxesAndGrid: Bool
    let onSelectReplayIndex: (Int) -> Void

    @State private var mode = Mode.both
    @State private var selected: ReplayPoint?

    private var displayPoints: [ReplayPoint] {
        AnalyticsDisplaySampler.sample(points, limit: 1_200)
    }

    private var elevationBounds: (min: Double, max: Double) {
        let values = points.map(\.elevationMeters)
        return (values.min() ?? 0, values.max() ?? 1)
    }

    private var maximumSpeed: Double { points.map(\.speedKmh).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartTitle("Elevation & Speed Profile", detail: "The shape of the road and the rhythm of the ride")

            MLSegmentedControl(items: Mode.allCases, title: { $0.rawValue }, selection: $mode, compact: true)

            HStack(spacing: Spacing.md) {
                legend("Elevation", value: selected.map { "\(Int($0.elevationMeters.rounded())) m" } ?? elevationSummary, color: .mlAccent)
                legend("Speed", value: selected.map { "\(Int($0.speedKmh.rounded())) km/h" } ?? speedSummary, color: .mlInfo)
            }

            if points.count < 3 {
                analyticsEmpty("Not enough timed points for the combined profile.")
            } else {
                Chart {
                    if mode != .speed {
                        ForEach(displayPoints) { point in
                            LineMark(
                                x: .value("Distance", point.distanceKm),
                                y: .value("Elevation shape", normalizedElevation(point.elevationMeters))
                            )
                            .foregroundStyle(Color.mlAccent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    if mode != .elevation {
                        ForEach(displayPoints) { point in
                            LineMark(
                                x: .value("Distance", point.distanceKm),
                                y: .value("Speed shape", normalizedSpeed(point.speedKmh))
                            )
                            .foregroundStyle(Color.mlInfo)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Selection", selected.distanceKm))
                            .foregroundStyle(Color.mlTextSecondary.opacity(0.7))
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .chartXAxisLabel("Distance (km)")
                .analyticsXAxis(visible: showsAxesAndGrid)
                .overlay {
                    if showsAxesAndGrid {
                        profileScaleOverlay
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in select(value.location, proxy: proxy, geometry: geometry) }
                                    .onEnded { _ in
                                        guard let selected else { return }
                                        onSelectReplayIndex(selected.index)
                                    }
                            )
                    }
                }
                .frame(height: 220)
            }

            Text("The two lines use independent scales so their shapes can be compared; their vertical positions are not equal units.")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
        }
        .analyticsCard()
    }

    private var elevationSummary: String {
        "\(Int(elevationBounds.min.rounded()))–\(Int(elevationBounds.max.rounded())) m"
    }

    private var speedSummary: String { "max \(Int(maximumSpeed.rounded())) km/h" }

    private var profileScaleOverlay: some View {
        HStack {
            if mode != .speed {
                scaleLabels(
                    top: "\(Int(elevationBounds.max.rounded())) m",
                    bottom: "\(Int(elevationBounds.min.rounded())) m",
                    color: .mlAccent,
                    alignment: .leading
                )
            }
            Spacer()
            if mode != .elevation {
                scaleLabels(
                    top: "\(Int(maximumSpeed.rounded())) km/h",
                    bottom: "0 km/h",
                    color: .mlInfo,
                    alignment: .trailing
                )
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .allowsHitTesting(false)
    }

    private func scaleLabels(
        top: String,
        bottom: String,
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(top)
            Spacer()
            Text(bottom)
        }
        .font(MLFont.monoSmall)
        .foregroundStyle(color)
        .shadow(color: Color.mlBackground, radius: 3)
    }

    private func normalizedElevation(_ value: Double) -> Double {
        let span = elevationBounds.max - elevationBounds.min
        return span > 0 ? (value - elevationBounds.min) / span : 0.5
    }

    private func normalizedSpeed(_ value: Double) -> Double {
        maximumSpeed > 0 ? value / maximumSpeed : 0
    }

    private func legend(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).mlKicker()
                Text(value)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func select(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let distance: Double = proxy.value(atX: location.x - origin.x),
              let nearest = points.min(by: {
                  abs($0.distanceKm - distance) < abs($1.distanceKm - distance)
              }) else { return }
        if selected?.id != nearest.id { Haptics.selection() }
        selected = nearest
    }
}

private struct RideCompositionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let slices: [RideCompositionSlice]

    private var total: TimeInterval { slices.map(\.seconds).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Ride Rhythm")
            Chart(slices) { slice in
                BarMark(
                    x: .value("Time", slice.seconds),
                    y: .value("Ride", "Composition")
                )
                .foregroundStyle(color(for: slice.kind))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: Spacing.lg)
            .clipShape(Capsule())

            LazyVGrid(columns: compositionColumns, spacing: Spacing.xs) {
                ForEach(slices.filter { $0.seconds > 0 }) { slice in
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(color(for: slice.kind))
                            .frame(width: Spacing.xs, height: Spacing.xs)
                        Text(slice.kind.rawValue)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                        Spacer()
                        Text(percent(slice))
                            .font(MLFont.monoSmall)
                            .foregroundStyle(Color.mlTextPrimary)
                    }
                }
            }
        }
        .analyticsCard()
    }

    private var compositionColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func percent(_ slice: RideCompositionSlice) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((100 * slice.seconds / total).rounded()))%"
    }

    private func color(for kind: RideCompositionSlice.Kind) -> Color {
        switch kind {
        case .cornering: .mlAccent
        case .braking: .mlDanger
        case .driving: .mlSuccess
        case .cruising: .mlInfo
        case .stopped: .mlTextTertiary
        }
    }
}

private struct InputProfileChart: View {
    let analytics: RideAnalytics
    let showsAxesAndGrid: Bool
    let onSelectReplayIndex: (Int) -> Void
    @State private var selected: RideAccelerationSample?

    private var displayAcceleration: [RideAccelerationSample] {
        AnalyticsDisplaySampler.sample(analytics.acceleration, limit: 1_200)
    }

    private var range: ClosedRange<Double> {
        let values = analytics.acceleration.map(\.acceleration)
        let lower = min(values.min() ?? -1, -1)
        let upper = max(values.max() ?? 1, 1)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartTitle("Acceleration Profile", detail: "Brake, corner, drive, cruise")
            AnalyticsLegend(items: [
                .init(title: "Acceleration", color: .mlInfo, style: .line),
                .init(title: "Braking", color: .mlDanger, style: .area),
                .init(title: "Drive", color: .mlSuccess, style: .area)
            ])
            Chart {
                ForEach(analytics.brakingZones) { zone in
                    RectangleMark(
                        xStart: .value("Start", zone.startKm),
                        xEnd: .value("End", zone.endKm),
                        yStart: .value("Low", range.lowerBound),
                        yEnd: .value("High", range.upperBound)
                    )
                    .foregroundStyle(Color.mlDanger.opacity(0.12))
                }
                ForEach(analytics.driveZones) { zone in
                    RectangleMark(
                        xStart: .value("Start", zone.startKm),
                        xEnd: .value("End", zone.endKm),
                        yStart: .value("Low", range.lowerBound),
                        yEnd: .value("High", range.upperBound)
                    )
                    .foregroundStyle(Color.mlSuccess.opacity(0.1))
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.mlHairline)
                ForEach(displayAcceleration) { sample in
                    LineMark(
                        x: .value("Distance", sample.distanceKm),
                        y: .value("Acceleration", sample.acceleration)
                    )
                    .foregroundStyle(Color.mlInfo)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                if let selected {
                    RuleMark(x: .value("Selection", selected.distanceKm))
                        .foregroundStyle(Color.mlTextSecondary.opacity(0.6))
                    PointMark(
                        x: .value("Distance", selected.distanceKm),
                        y: .value("Acceleration", selected.acceleration)
                    )
                    .foregroundStyle(Color.mlAccent)
                }
            }
            .chartYScale(domain: range)
            .chartXAxisLabel("Distance (km)")
            .chartYAxisLabel("Acceleration (m/s²)")
            .analyticsAxes(visible: showsAxesAndGrid)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    scrub(value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    guard let selected else { return }
                                    onSelectReplayIndex(selected.index)
                                }
                        )
                }
            }
            .frame(height: 190)
        }
        .analyticsCard()
    }

    private func scrub(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let distance: Double = proxy.value(atX: location.x - origin.x),
              let nearest = analytics.acceleration.min(by: {
                  abs($0.distanceKm - distance) < abs($1.distanceKm - distance)
              }) else { return }
        if selected?.id != nearest.id { Haptics.selection() }
        selected = nearest
    }
}

private struct CornerRadiusChart: View {
    let points: [CornerAnalyticsPoint]
    let showsAxesAndGrid: Bool
    let onSelectReplayIndex: (Int) -> Void
    @State private var selected: CornerAnalyticsPoint?

    private var visiblePoints: [CornerAnalyticsPoint] {
        points.filter { $0.radiusMeters <= 320 }
    }

    private var references: [GripReferencePoint] {
        [0.2, 0.35, 0.5].flatMap { level in
            stride(from: 15.0, through: 320.0, by: 5).map { radius in
                GripReferencePoint(
                    level: level,
                    radius: radius,
                    speedKmh: sqrt(level * 9.81 * radius) * 3.6
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartTitle("Corner Speed vs Radius", detail: "Tap a corner to replay it")
            AnalyticsLegend(items: [
                .init(title: "Corners", color: .mlAccent, style: .point),
                .init(title: "0.20 g", color: .mlInfo, style: .dash),
                .init(title: "0.35 g", color: .mlWarning, style: .dash),
                .init(title: "0.50 g", color: .mlDanger, style: .dash)
            ])
            if visiblePoints.isEmpty {
                analyticsEmpty("No significant corners available for this chart.")
            } else {
                Chart {
                    ForEach(references) { point in
                        LineMark(
                            x: .value("Radius", point.radius),
                            y: .value("Reference speed", point.speedKmh)
                        )
                        .foregroundStyle(by: .value("Estimated lateral load", point.label))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(visiblePoints) { point in
                        PointMark(
                            x: .value("Radius", point.radiusMeters),
                            y: .value("Apex speed", point.apexKmh)
                        )
                        .foregroundStyle(selected?.id == point.id ? Color.mlTextPrimary : Color.mlAccent)
                        .symbolSize(selected?.id == point.id ? 110 : 70)
                    }
                }
                .chartForegroundStyleScale([
                    "0.20 g": Color.mlInfo,
                    "0.35 g": Color.mlWarning,
                    "0.50 g": Color.mlDanger
                ])
                .chartLegend(.hidden)
                .chartXAxisLabel("Corner radius (m)")
                .chartYAxisLabel("Apex speed (km/h)")
                .analyticsAxes(visible: showsAxesAndGrid)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                                select(value.location, proxy: proxy, geometry: geometry)
                            })
                    }
                }
                .frame(height: 230)
            }
        }
        .analyticsCard()
    }

    private func select(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let radius: Double = proxy.value(atX: location.x - origin.x),
              let speed: Double = proxy.value(atY: location.y - origin.y),
              let nearest = visiblePoints.min(by: {
                  distance($0, radius: radius, speed: speed) < distance($1, radius: radius, speed: speed)
              }) else { return }
        selected = nearest
        Haptics.selection()
        onSelectReplayIndex(nearest.replayIndex)
    }

    private func distance(_ point: CornerAnalyticsPoint, radius: Double, speed: Double) -> Double {
        hypot((point.radiusMeters - radius) / 100, (point.apexKmh - speed) / 50)
    }
}

private struct GripUsageChart: View {
    let points: [GripUsagePoint]
    let showsAxesAndGrid: Bool

    private var displayPoints: [GripUsagePoint] {
        AnalyticsDisplaySampler.sample(points, limit: 1_000)
    }

    private var domain: ClosedRange<Double> {
        let peak = points.flatMap { [abs($0.lateralG), abs($0.longitudinalG)] }.max() ?? 0.5
        let bound = min(max(ceil(peak * 10) / 10, 0.5), 1.2)
        return -bound...bound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartTitle("Grip Usage", detail: "Left/right cornering, braking below, drive above")
            AnalyticsLegend(items: [
                .init(title: "Cornering", color: .mlAccent, style: .point),
                .init(title: "Braking", color: .mlDanger, style: .point),
                .init(title: "Drive", color: .mlSuccess, style: .point)
            ])
            if points.isEmpty {
                analyticsEmpty("Not enough moving GPS points for a grip-usage view.")
            } else {
                Chart {
                    RuleMark(x: .value("Centre", 0)).foregroundStyle(Color.mlHairline)
                    RuleMark(y: .value("Centre", 0)).foregroundStyle(Color.mlHairline)
                    ForEach(displayPoints) { point in
                        PointMark(
                            x: .value("Lateral g", point.lateralG),
                            y: .value("Longitudinal g", point.longitudinalG)
                        )
                        .foregroundStyle(gripColor(point).opacity(0.45))
                        .symbolSize(12)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: domain)
                .chartXAxisLabel("Cornering (g)")
                .chartYAxisLabel("Brake / drive (g)")
                .analyticsAxes(visible: showsAxesAndGrid)
                .frame(height: 260)
                .accessibilityLabel("Approximate grip usage scatter plot")
            }
        }
        .analyticsCard()
    }

    private func gripColor(_ point: GripUsagePoint) -> Color {
        if point.longitudinalG < -0.12 { return .mlDanger }
        if point.longitudinalG > 0.12 { return .mlSuccess }
        return .mlAccent
    }
}

private struct RideCoachTechniqueView: View {
    let scores: [RideCoachScore]
    let debrief: String?
    let trend: String?
    let showsAxesAndGrid: Bool

    @State private var showsBreakdown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            chartTitle("Ride Coach", detail: "Five views of technique balance, never a speed target")

            if let debrief {
                Label(debrief, systemImage: "quote.opening")
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.md)
                    .background(Color.mlAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }

            if scores.count >= 3 {
                TechniquePolygon(scores: scores, showsAxesAndGrid: showsAxesAndGrid)
                    .frame(height: 280)

                if showsAxesAndGrid {
                    Label("Centre 0 · outer ring 100", systemImage: "scope")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let trend {
                    Label(trend, systemImage: "chart.line.uptrend.xyaxis")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : Motion.spring) { showsBreakdown.toggle() }
                } label: {
                    Label(
                        showsBreakdown ? "Hide score breakdown" : "Read the five axes",
                        systemImage: showsBreakdown ? "chevron.up" : "chevron.down"
                    )
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlAccent)
                    .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                }
                .buttonStyle(MLPressableButtonStyle())

                if showsBreakdown {
                    VStack(spacing: Spacing.md) {
                        ForEach(orderedScores) { score in
                            scoreRow(score)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                analyticsEmpty("Not enough detected corners and input zones for the Ride Coach polygon.")
            }

            Text("GPS-derived technique estimates. Compare shape and captions across your own rides; do not chase a larger polygon on public roads.")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .analyticsCard()
    }

    private var orderedScores: [RideCoachScore] {
        RideCoachScore.Kind.allCases.compactMap { kind in scores.first { $0.kind == kind } }
    }

    private func scoreRow(_ score: RideCoachScore) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Label(score.kind.title, systemImage: score.kind.symbol)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                Spacer()
                Text("\(score.value)")
                    .font(MLFont.mono)
                    .foregroundStyle(Color.mlAccent)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mlSurfaceElevated)
                    Capsule()
                        .fill(Color.mlAccent)
                        .frame(width: geometry.size.width * CGFloat(score.value) / 100)
                }
            }
            .frame(height: 6)
            Text(score.caption)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TechniquePolygon: View {
    let scores: [RideCoachScore]
    let showsAxesAndGrid: Bool

    private let labels = ["Entry", "Exit", "Brake", "Throttle", "Repeat"]

    private var values: [Double] {
        RideCoachScore.Kind.allCases.map { kind in
            Double(scores.first { $0.kind == kind }?.value ?? 0) / 100
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = max(40, min(geometry.size.width, geometry.size.height) / 2 - 42)

            ZStack {
                Canvas { context, _ in
                    if showsAxesAndGrid {
                        for level in [0.25, 0.5, 0.75, 1.0] {
                            context.stroke(
                                polygonPath(center: center, radius: radius, values: Array(repeating: level, count: 5)),
                                with: .color(Color.mlHairline.opacity(level == 1 ? 0.8 : 0.45)),
                                lineWidth: level == 1 ? 1.2 : 0.8
                            )
                        }

                        for index in 0..<5 {
                            var axis = Path()
                            axis.move(to: center)
                            axis.addLine(to: point(index: index, scale: 1, center: center, radius: radius))
                            context.stroke(axis, with: .color(Color.mlHairline.opacity(0.6)), lineWidth: 0.8)
                        }
                    }

                    let scorePath = polygonPath(center: center, radius: radius, values: values)
                    context.fill(scorePath, with: .color(Color.mlAccent.opacity(0.18)))
                    context.stroke(scorePath, with: .color(Color.mlAccent), lineWidth: 2.5)

                    for index in values.indices {
                        let marker = point(index: index, scale: values[index], center: center, radius: radius)
                        context.fill(
                            Path(ellipseIn: CGRect(x: marker.x - 4, y: marker.y - 4, width: 8, height: 8)),
                            with: .color(Color.mlAccent)
                        )
                    }
                }

                ForEach(labels.indices, id: \.self) { index in
                    let location = point(index: index, scale: 1.23, center: center, radius: radius)
                    VStack(spacing: 1) {
                        Text(labels[index])
                            .font(MLFont.kicker)
                        Text("\(Int((values[index] * 100).rounded()))")
                            .font(MLFont.monoSmall)
                            .foregroundStyle(Color.mlAccent)
                    }
                    .foregroundStyle(Color.mlTextSecondary)
                        .position(location)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride Coach technique polygon")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        zip(labels, values).map { "\($0.0) \(Int(($0.1 * 100).rounded()))" }.joined(separator: ", ")
    }

    private func polygonPath(center: CGPoint, radius: CGFloat, values: [Double]) -> Path {
        var path = Path()
        for index in values.indices {
            let location = point(index: index, scale: values[index], center: center, radius: radius)
            index == 0 ? path.move(to: location) : path.addLine(to: location)
        }
        path.closeSubpath()
        return path
    }

    private func point(index: Int, scale: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 5
        return CGPoint(
            x: center.x + cos(angle) * radius * scale,
            y: center.y + sin(angle) * radius * scale
        )
    }
}

private struct GripReferencePoint: Identifiable {
    let level: Double
    let radius: Double
    let speedKmh: Double

    var label: String { String(format: "%.2f g", level) }
    var id: String { "\(level)-\(radius)" }
}

private struct AnalyticsLegend: View {
    struct Item {
        enum Style { case line, dash, point, area }
        let title: String
        let color: Color
        let style: Style
    }

    let items: [Item]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76), alignment: .leading)],
            alignment: .leading,
            spacing: Spacing.xs
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: Spacing.xs) {
                    swatch(item)
                    Text(item.title)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(items.map(\.title).joined(separator: ", "))
    }

    @ViewBuilder
    private func swatch(_ item: Item) -> some View {
        switch item.style {
        case .point:
            Circle().fill(item.color).frame(width: 7, height: 7)
        case .area:
            RoundedRectangle(cornerRadius: 2)
                .fill(item.color.opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(item.color, lineWidth: 1))
                .frame(width: 18, height: 8)
        case .line:
            Capsule().fill(item.color).frame(width: 20, height: 2)
        case .dash:
            HStack(spacing: 2) {
                Capsule().fill(item.color).frame(width: 7, height: 2)
                Capsule().fill(item.color).frame(width: 7, height: 2)
            }
        }
    }
}

@MainActor
private func chartTitle(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(title)
            .font(MLFont.title2)
            .foregroundStyle(Color.mlTextPrimary)
        Text(detail)
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextSecondary)
    }
}

@MainActor
private func analyticsEmpty(_ message: String) -> some View {
    Text(message)
        .font(MLFont.callout)
        .foregroundStyle(Color.mlTextSecondary)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
}

private extension View {
    func analyticsCard() -> some View {
        padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
    }

    func analyticsAxes(visible: Bool) -> some View {
        modifier(AnalyticsAxesModifier(visible: visible))
    }

    func analyticsXAxis(visible: Bool) -> some View {
        modifier(AnalyticsXAxisModifier(visible: visible))
    }
}

private struct AnalyticsAxesModifier: ViewModifier {
    let visible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if visible {
            content
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color.mlHairline.opacity(0.5))
                        AxisValueLabel().foregroundStyle(Color.mlTextTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.mlHairline)
                        AxisValueLabel().foregroundStyle(Color.mlTextTertiary)
                    }
                }
        } else {
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        }
    }
}

private struct AnalyticsXAxisModifier: ViewModifier {
    let visible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if visible {
            content.chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.mlHairline.opacity(0.5))
                    AxisValueLabel().foregroundStyle(Color.mlTextTertiary)
                }
            }
        } else {
            content.chartXAxis(.hidden)
        }
    }
}

#Preview("Ride Analytics") {
    ScrollView {
        RideAnalyticsView(
            analytics: .empty,
            replayPoints: [],
            coachScores: [],
            debrief: nil,
            coachTrend: nil,
            onSelectReplayIndex: { _ in }
        )
            .padding()
    }
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
