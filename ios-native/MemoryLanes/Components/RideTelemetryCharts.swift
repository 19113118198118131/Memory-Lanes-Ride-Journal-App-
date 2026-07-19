import SwiftUI
import Charts

struct SpeedChart: View {
    let points: [ReplayPoint]
    var playbackPoint: ReplayPoint? = nil
    var onScrub: ((Int) -> Void)? = nil
    @State private var selected: ReplayPoint?

    private var highlightedPoint: ReplayPoint? {
        selected ?? playbackPoint
    }

    private var maxSpeed: Double {
        points.map(\.speedKmh).max() ?? 0
    }

    private var averageSpeed: Double {
        guard let last = points.last, last.elapsedSeconds > 0 else { return 0 }
        return last.distanceKm / (last.elapsedSeconds / 3600)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartHeader(
                title: "Speed",
                primary: String(format: "%.0f km/h", maxSpeed),
                secondary: String(format: "avg %.0f km/h", averageSpeed),
                selectedValue: highlightedPoint.map { String(format: "%.0f km/h", $0.speedKmh) },
                selectedDistance: highlightedPoint.map { String(format: "%.1f km", $0.distanceKm) }
            )

            Chart(points) { point in
                AreaMark(
                    x: .value("Distance", point.distanceKm),
                    y: .value("Speed", point.speedKmh)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.mlInfo.opacity(0.28), Color.mlInfo.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Distance", point.distanceKm),
                    y: .value("Speed", point.speedKmh)
                )
                .foregroundStyle(Color.mlInfo)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                if let highlightedPoint, highlightedPoint.id == point.id {
                    RuleMark(x: .value("Distance", highlightedPoint.distanceKm))
                        .foregroundStyle(Color.mlTextSecondary.opacity(0.5))
                    PointMark(
                        x: .value("Distance", highlightedPoint.distanceKm),
                        y: .value("Speed", highlightedPoint.speedKmh)
                    )
                    .foregroundStyle(Color.mlInfo)
                    .symbolSize(110)
                }
            }
            .mlTelemetryAxes()
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in scrub(at: value.location, proxy: proxy, geo: geo) }
                                .onEnded { _ in selected = nil }
                        )
                }
            }
            .frame(height: 170)
        }
        .telemetryCard()
    }

    private func scrub(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        guard let distance: Double = proxy.value(atX: point.x - origin.x) else { return }
        let nearest = points.min {
            abs($0.distanceKm - distance) < abs($1.distanceKm - distance)
        }
        if nearest?.id != selected?.id {
            Haptics.selection()
        }
        selected = nearest
        if let nearest {
            onScrub?(nearest.index)
        }
    }
}

struct AccelerationChart: View {
    let points: [ReplayPoint]
    var playbackIndex: Int? = nil
    var onScrub: ((Int) -> Void)? = nil
    @State private var selected: AccelerationSample?

    private var highlightedSample: AccelerationSample? {
        if let selected { return selected }
        guard let playbackIndex else { return nil }
        return samples.min { abs($0.id - playbackIndex) < abs($1.id - playbackIndex) }
    }

    private var samples: [AccelerationSample] {
        AccelerationSample.samples(from: points)
    }

    private var peakAcceleration: Double {
        samples.map(\.acceleration).max() ?? 0
    }

    private var peakBraking: Double {
        abs(samples.map(\.acceleration).min() ?? 0)
    }

    var body: some View {
        let samples = samples
        VStack(alignment: .leading, spacing: Spacing.sm) {
            chartHeader(
                title: "Acceleration",
                primary: String(format: "+%.1f m/s²", peakAcceleration),
                secondary: String(format: "-%.1f braking", peakBraking),
                selectedValue: highlightedSample.map { String(format: "%+.1f m/s²", $0.acceleration) },
                selectedDistance: highlightedSample.map { String(format: "%.1f km", $0.distanceKm) }
            )

            Chart(samples) { sample in
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.mlHairline)

                LineMark(
                    x: .value("Distance", sample.distanceKm),
                    y: .value("Acceleration", sample.acceleration)
                )
                .foregroundStyle(sample.acceleration >= 0 ? Color.mlSuccess : Color.mlWarning)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                if let highlightedSample, highlightedSample.id == sample.id {
                    RuleMark(x: .value("Distance", highlightedSample.distanceKm))
                        .foregroundStyle(Color.mlTextSecondary.opacity(0.5))
                    PointMark(
                        x: .value("Distance", highlightedSample.distanceKm),
                        y: .value("Acceleration", highlightedSample.acceleration)
                    )
                    .foregroundStyle(highlightedSample.acceleration >= 0 ? Color.mlSuccess : Color.mlWarning)
                    .symbolSize(110)
                }
            }
            .mlTelemetryAxes()
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in scrub(at: value.location, proxy: proxy, geo: geo, samples: samples) }
                                .onEnded { _ in selected = nil }
                        )
                }
            }
            .frame(height: 170)
        }
        .telemetryCard()
    }

    private func scrub(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy, samples: [AccelerationSample]) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        guard let distance: Double = proxy.value(atX: point.x - origin.x) else { return }
        let nearest = samples.min {
            abs($0.distanceKm - distance) < abs($1.distanceKm - distance)
        }
        if nearest?.id != selected?.id {
            Haptics.selection()
        }
        selected = nearest
        if let nearest {
            onScrub?(nearest.id)
        }
    }
}

private struct AccelerationSample: Identifiable, Hashable {
    let id: Int
    let distanceKm: Double
    let acceleration: Double

    static func samples(from points: [ReplayPoint]) -> [AccelerationSample] {
        guard points.count > 2 else { return [] }
        return points.indices.dropFirst().dropLast().compactMap { index in
            let previous = points[index - 1]
            let next = points[index + 1]
            let dt = next.elapsedSeconds - previous.elapsedSeconds
            guard dt > 0 else { return nil }
            let previousSpeed = previous.speedKmh / 3.6
            let nextSpeed = next.speedKmh / 3.6
            return AccelerationSample(
                id: index,
                distanceKm: points[index].distanceKm,
                acceleration: (nextSpeed - previousSpeed) / dt
            )
        }
    }
}

@MainActor
private func chartHeader(
    title: String,
    primary: String,
    secondary: String,
    selectedValue: String?,
    selectedDistance: String?
) -> some View {
    HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).mlKicker()
            Text(primary)
                .font(MLFont.displaySmall)
                .foregroundStyle(Color.mlTextPrimary)
            Text(secondary)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
        }
        Spacer()
        if let selectedValue, let selectedDistance {
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(selectedValue)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlAccent)
                Text(selectedDistance)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlTextSecondary)
            }
        }
    }
}

private extension View {
    func telemetryCard() -> some View {
        padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
    }

    func mlTelemetryAxes() -> some View {
        chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.mlHairline)
                AxisValueLabel().foregroundStyle(Color.mlTextTertiary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.mlHairline.opacity(0.5))
                AxisValueLabel().foregroundStyle(Color.mlTextTertiary)
            }
        }
    }
}

#Preview("Telemetry Charts") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            SpeedChart(points: SampleData.replayPoints)
            AccelerationChart(points: SampleData.replayPoints)
        }
        .padding()
    }
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
