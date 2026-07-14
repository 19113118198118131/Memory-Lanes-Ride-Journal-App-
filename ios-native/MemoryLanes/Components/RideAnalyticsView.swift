import Charts
import SwiftUI

struct RideAnalyticsView: View {
    let analytics: RideAnalytics
    let onSelectReplayIndex: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            approximationLabel
            RideCompositionView(slices: analytics.composition)
            inputSummary
            InputProfileChart(analytics: analytics, onSelectReplayIndex: onSelectReplayIndex)
            CornerRadiusChart(points: analytics.cornerPoints, onSelectReplayIndex: onSelectReplayIndex)
            GripUsageChart(points: analytics.gripUsage)
            insightSection
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

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "What This Ride Says")
            ForEach(Array(analytics.insights.enumerated()), id: \.element.id) { index, insight in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(insightTitle(insight.kind), systemImage: insightSymbol(insight.kind))
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
                if index < analytics.insights.count - 1 {
                    Divider().overlay(Color.mlHairline)
                }
            }
        }
    }

    private func insightTitle(_ kind: RideAnalyticsInsight.Kind) -> String {
        switch kind {
        case .grip: "Riding Signature"
        case .corners: "Corner Rhythm"
        case .elevation: "Road Shape"
        case .inputs: "Brake & Throttle"
        }
    }

    private func insightSymbol(_ kind: RideAnalyticsInsight.Kind) -> String {
        switch kind {
        case .grip: "circle.hexagongrid.fill"
        case .corners: "point.topleft.down.to.point.bottomright.curvepath"
        case .elevation: "mountain.2.fill"
        case .inputs: "gauge.with.dots.needle.67percent"
        }
    }
}

private struct RideCompositionView: View {
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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
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
    let onSelectReplayIndex: (Int) -> Void
    @State private var selected: RideAccelerationSample?

    private var range: ClosedRange<Double> {
        let values = analytics.acceleration.map(\.acceleration)
        let lower = min(values.min() ?? -1, -1)
        let upper = max(values.max() ?? 1, 1)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartTitle("Acceleration Profile", detail: "Brake, corner, drive, cruise")
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
                ForEach(analytics.acceleration) { sample in
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
            .analyticsAxes()
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            scrub(value.location, proxy: proxy, geometry: geometry)
                        })
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
        onSelectReplayIndex(nearest.index)
    }
}

private struct CornerRadiusChart: View {
    let points: [CornerAnalyticsPoint]
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
                .chartXAxisLabel("Corner radius (m)")
                .chartYAxisLabel("Apex speed (km/h)")
                .analyticsAxes()
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

    private var domain: ClosedRange<Double> {
        let peak = points.flatMap { [abs($0.lateralG), abs($0.longitudinalG)] }.max() ?? 0.5
        let bound = min(max(ceil(peak * 10) / 10, 0.5), 1.2)
        return -bound...bound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartTitle("Grip Usage", detail: "Left/right cornering, braking below, drive above")
            if points.isEmpty {
                analyticsEmpty("Not enough moving GPS points for a grip-usage view.")
            } else {
                Chart {
                    RuleMark(x: .value("Centre", 0)).foregroundStyle(Color.mlHairline)
                    RuleMark(y: .value("Centre", 0)).foregroundStyle(Color.mlHairline)
                    ForEach(points) { point in
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
                .analyticsAxes()
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

private struct GripReferencePoint: Identifiable {
    let level: Double
    let radius: Double
    let speedKmh: Double

    var label: String { String(format: "%.2f g", level) }
    var id: String { "\(level)-\(radius)" }
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

    func analyticsAxes() -> some View {
        chartXAxis {
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
    }
}

#Preview("Ride Analytics") {
    ScrollView {
        RideAnalyticsView(analytics: .empty, onSelectReplayIndex: { _ in })
            .padding()
    }
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
