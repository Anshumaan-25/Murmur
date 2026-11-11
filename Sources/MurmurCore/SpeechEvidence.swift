import Foundation

/// Classifier evidence, never inferred from volume or decoder text. Uncertain
/// audio is still decoded and can be reviewed; it cannot authorize automatic edits.
public struct SpeechEvidence: Sendable {
    public private(set) var analyzedThrough: Double = 0
    public var lastSpeechEnd: Double? { standard.lastEnd }
    public var speechSeconds: Double { standard.seconds }
    private var standard = Coverage()
    private var held = Coverage()
    private var completedDuration: Double = 0
    private var lastUncertainEnd: Double = 0
    private var failed = false
    private var completed = false
    public init() {}
    public var heardSpeech: Bool { !failed && lastSpeechEnd != nil }
    public var silence: Double { heardSpeech ? max(0, analyzedThrough - max(lastSpeechEnd ?? 0, lastUncertainEnd)) : 0 }
    private var duration: Double { completed ? completedDuration : analyzedThrough }
    public var unqualifiedSeconds: Double { max(0, duration - speechSeconds) }
    public var longestUnqualifiedSpan: Double { standard.longestGap(through: duration) }
    public var allowsAutomaticDelivery: Bool { deliveryBlock(held: false) == "ready" }

    /// A deliberate hold can include moderately confident speech next to a strong
    /// speech window. The same full-clip coverage rules still apply.
    public var allowsHeldDictationDelivery: Bool { deliveryBlock(held: true) == "ready" }

    public func deliveryBlock(held useHeld: Bool) -> String {
        if failed { return "analysis_failed" }
        if !completed { return "incomplete" }
        let coverage = useHeld ? held : standard
        if !coverage.sustained { return "no_sustained_speech" }
        if coverage.longestGap(through: duration) > 3 { return "long_unqualified_gap" }
        if max(0, duration - coverage.seconds) > coverage.seconds + 2 { return "insufficient_coverage" }
        return "ready"
    }

    public func diagnostic(held: Bool) -> [String: Any] {
        ["reason": deliveryBlock(held: held), "held": held, "completed": completed,
         "failed": failed, "analyzed_seconds": analyzedThrough, "duration_seconds": duration,
         "speech_seconds": (held ? self.held : standard).seconds,
         "longest_gap_seconds": (held ? self.held : standard).longestGap(through: duration)]
    }

    public mutating func observe(start: Double, end: Double, confidence: Double) {
        guard !failed, !completed else { return }
        guard start.isFinite, end.isFinite, confidence.isFinite, start >= 0,
              end > start, end > analyzedThrough, start <= analyzedThrough, (0...1).contains(confidence) else { fail(); return }
        analyzedThrough = end
        standard.observe(start: start, end: end, confidence: confidence, threshold: 0.8)
        held.observe(start: start, end: end, confidence: confidence, threshold: 0.75)
        // Keep the intermediate band from counting as clear silence.
        if confidence < 0.8, confidence > 0.3 { lastUncertainEnd = end }
    }
    public mutating func complete(duration: Double? = nil) {
        guard !completed else { return }
        let duration = duration ?? analyzedThrough
        // The 50%-overlapped 0.5s classifier can leave less than one 0.25s
        // hop at the end. Longer missing coverage must never grant authority.
        guard duration.isFinite, duration >= analyzedThrough,
              duration - analyzedThrough <= 0.25 + 1 / AudioTools.rate else { fail(); return }
        completedDuration = duration
        completed = true
    }
    public mutating func fail() { failed = true }

    private struct Coverage: Sendable {
        var lastEnd: Double?
        var seconds: Double = 0
        var longestClosedGap: Double = 0
        var previousConfidence: Double?
        var sustained = false

        mutating func observe(start: Double, end: Double, confidence: Double, threshold: Double) {
            guard confidence >= threshold else {
                previousConfidence = nil
                return
            }
            let previousEnd = lastEnd ?? 0
            longestClosedGap = max(longestClosedGap, start - previousEnd)
            // Union of overlapping qualified windows.
            seconds += end - max(start, previousEnd)
            lastEnd = end
            if let previousConfidence, max(previousConfidence, confidence) >= 0.8 { sustained = true }
            previousConfidence = confidence
        }

        func longestGap(through duration: Double) -> Double {
            max(longestClosedGap, duration - (lastEnd ?? 0))
        }

    }
}
