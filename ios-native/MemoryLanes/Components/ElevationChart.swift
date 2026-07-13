import SwiftUI
import Charts

// MARK: - ElevationChart
//
// A filled area chart of elevation over distance, built with Swift Charts (no
// third-party library). Drag to scrub: a rule mark and a floating readout track
// the finger. Includes an accessibility chart descriptor for VoiceOver.

struct ElevationChart: View {
    let samples: [ElevationSample]
    @State private var selected: ElevationSample?

    private var gainText: String {
        guard let maxE = samples.map(\.elevationM).max(),
              let minE = samples.map(\.elevationM).min() else { return "—" }
        return String(format: "%.0f m", maxE - minE)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elevation").mlKicker()
                    Text(gainText)
                        .font(MLFont.displaySmall)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f m", selected.elevationM))
                            .font(MLFont.monoSmall)
                            .foregroundStyle(Color.mlAccent)
                        Text(String(format: "%.1f km", selected.distanceKm))
                            .font(MLFont.monoSmall)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                }
            }

            Chart(samples) { sample in
                AreaMark(
                    x: .value("Distance", sample.distanceKm),
                    y: .value("Elevation", sample.elevationM)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.mlAccent.opacity(0.35), Color.mlAccent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Distance", sample.distanceKm),
                    y: .value("Elevation", sample.elevationM)
                )
                .foregroundStyle(Color.mlAccent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                if let selected, selected.id == sample.id {
                    RuleMark(x: .value("Distance", selected.distanceKm))
                        .foregroundStyle(Color.mlTextSecondary.opacity(0.5))
                    PointMark(
                        x: .value("Distance", selected.distanceKm),
                        y: .value("Elevation", selected.elevationM)
                    )
                    .foregroundStyle(Color.mlAccent)
                    .symbolSize(120)
                }
            }
            .chartYAxis {
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
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    scrub(at: value.location, proxy: proxy, geo: geo)
                                }
                                .onEnded { _ in selected = nil }
                        )
                }
            }
            .frame(height: 180)
            .accessibilityChartDescriptor(self)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func scrub(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        let xPos = point.x - origin.x
        guard let distance: Double = proxy.value(atX: xPos) else { return }
        let nearest = samples.min(by: {
            abs($0.distanceKm - distance) < abs($1.distanceKm - distance)
        })
        if nearest?.id != selected?.id {
            Haptics.selection()
        }
        selected = nearest
    }
}

// MARK: - Accessibility chart descriptor

extension ElevationChart: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let xValues = samples.map(\.distanceKm)
        let yValues = samples.map(\.elevationM)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Distance (km)",
            range: (xValues.min() ?? 0)...(xValues.max() ?? 1),
            gridlinePositions: []
        ) { String(format: "%.1f km", $0) }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Elevation (m)",
            range: (yValues.min() ?? 0)...(yValues.max() ?? 1),
            gridlinePositions: []
        ) { String(format: "%.0f m", $0) }

        let series = AXDataSeriesDescriptor(
            name: "Elevation profile",
            isContinuous: true,
            dataPoints: samples.map {
                .init(x: $0.distanceKm, y: $0.elevationM)
            }
        )

        return AXChartDescriptor(
            title: "Elevation over distance",
            summary: "Elevation profile of the ride",
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }
}

// MARK: - Previews

#Preview("ElevationChart") {
    ElevationChart(samples: SampleData.elevationSamples)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mlBackground)
        .preferredColorScheme(.dark)
}
