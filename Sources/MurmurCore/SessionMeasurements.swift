import Foundation

public struct SessionMeasurements: Sendable {
    public private(set) var feedbackMilliseconds: [Double] = []
    public private(set) var insertionMilliseconds: [Double] = []
    public init() {}
    public mutating func feedback(trigger: Double, painted: Double) {
        let elapsed = (painted - trigger) * 1000
        guard elapsed.isFinite, elapsed >= 0, elapsed < 10000 else { return }
        feedbackMilliseconds.append(elapsed); feedbackMilliseconds = Array(feedbackMilliseconds.suffix(100))
    }
    public mutating func insertion(released: Double, finished: Double) {
        let elapsed = (finished - released) * 1000
        guard elapsed.isFinite, elapsed >= 0 else { return }
        insertionMilliseconds.append(elapsed); insertionMilliseconds = Array(insertionMilliseconds.suffix(100))
    }
    public static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted(); guard !sorted.isEmpty else { return nil }
        return sorted.count % 2 == 0 ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
    }
}
