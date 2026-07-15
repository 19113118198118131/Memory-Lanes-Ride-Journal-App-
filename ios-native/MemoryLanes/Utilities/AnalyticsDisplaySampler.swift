import Foundation

/// Produces a stable display-only sample while retaining the first and last
/// values. Full-resolution arrays remain available to replay and analyzers;
/// Swift Charts simply does not need tens of thousands of marks to represent a
/// phone-sized plot.
enum AnalyticsDisplaySampler {
    static func sample<Element>(_ values: [Element], limit: Int) -> [Element] {
        guard limit > 0, !values.isEmpty else { return [] }
        guard values.count > limit else { return values }
        guard limit > 1 else { return [values[0]] }

        let step = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { offset in
            let index = min(values.count - 1, Int((Double(offset) * step).rounded()))
            return values[index]
        }
    }
}
