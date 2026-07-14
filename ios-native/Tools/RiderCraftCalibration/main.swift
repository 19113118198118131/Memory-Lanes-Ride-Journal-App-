import Foundation

private struct CalibrationRide: Encodable {
    struct Event: Encodable {
        let kind: String
        let cornerIndex: Int
        let replayIndex: Int
        let measuredValue: Double
        let threshold: Double
    }

    let source: String
    let pointCount: Int
    let cornerCount: Int
    let eventCount: Int
    let eventsPerCorner: Double?
    let unavailableReason: String?
    let events: [Event]

    init(url: URL, pointCount: Int, analysis: RiderCraftAnalysis) {
        source = url.deletingPathExtension().lastPathComponent
        self.pointCount = pointCount
        cornerCount = analysis.detectedCornerCount
        eventCount = analysis.events.count
        eventsPerCorner = analysis.eventsPerCorner
        unavailableReason = analysis.unavailableReason
        events = analysis.events.map {
            Event(
                kind: $0.kind.rawValue,
                cornerIndex: $0.cornerIndex,
                replayIndex: $0.replayIndex,
                measuredValue: $0.measuredValue,
                threshold: $0.threshold
            )
        }
    }
}

private struct CalibrationRun: Encodable {
    let report: RiderCraftCalibrationReport
    let rides: [CalibrationRide]
}

@main
private enum RiderCraftCalibrationCLI {
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard let directoryArgument = arguments.first else {
            throw CalibrationCLIError.usage
        }

        let directory = URL(fileURLWithPath: directoryArgument, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "gpx" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw CalibrationCLIError.noGPXFiles }

        let rides = try files.map { url -> (RiderCraftAnalysis, CalibrationRide) in
            let track = try GPXParser().parse(data: Data(contentsOf: url))
            let analysis = RideCoachAnalyzer().analyze(points: track.points).riderCraft
            return (analysis, CalibrationRide(url: url, pointCount: track.points.count, analysis: analysis))
        }
        let run = CalibrationRun(
            report: RiderCraftCalibrationReport(analyses: rides.map(\.0)),
            rides: rides.map(\.1)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(run)

        if arguments.count > 1 {
            let output = URL(fileURLWithPath: String(arguments[arguments.index(after: arguments.startIndex)]))
            try data.write(to: output, options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}

private enum CalibrationCLIError: LocalizedError {
    case usage
    case noGPXFiles

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: rider-craft-calibration <gpx-directory> [output.json]"
        case .noGPXFiles:
            "The calibration directory does not contain any GPX files."
        }
    }
}
