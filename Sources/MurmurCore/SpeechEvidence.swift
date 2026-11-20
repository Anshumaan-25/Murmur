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
    private struct Window: Sendable {
        let start, end, confidence: Double
    }
    private var windows: [Window] = []
    public init() {}
    public var completedSuccessfully: Bool { completed && !failed }
    // Even explicit opt-in needs a positive classifier window. A completed
    // analysis of non-speech cannot authorize insertion of a decoder guess.
    public var allowsUncertainShortRelease: Bool {
        completedSuccessfully && duration <= 3 && heardSpeech
    }
    public var heardSpeech: Bool { !failed && lastSpeechEnd != nil }
    public var silence: Double { heardSpeech ? max(0, analyzedThrough - max(lastSpeechEnd ?? 0, lastUncertainEnd)) : 0 }
    private var duration: Double { completed ? completedDuration : analyzedThrough }
    public var unqualifiedSeconds: Double { max(0, duration - speechSeconds) }
    public var longestUnqualifiedSpan: Double { standard.longestGap(through: duration) }
    public var allowsAutomaticDelivery: Bool { deliveryBlock(held: false) == "ready" }

    /// A deliberate hold can include moderately confident speech next to a strong
    /// speech window. The same full-clip coverage rules still apply.
    public var allowsHeldDictationDelivery: Bool { deliveryBlock(held: true) == "ready" }

    /// Additional eligibility only at the physical release of ordinary dictation.
    /// Times refer to the original PCM, before digital-silence trimming.
    public func releaseReason(text: String, frames: [AudioFrame]) -> String? {
        guard completedSuccessfully, !windows.isEmpty else { return nil }
        if windows.count == 1, let word = windows.first, word.start == 0,
           word.end >= 0.5, duration <= 0.65, word.confidence >= 0.95,
           text.range(of: #"^\s*\p{L}+(?:['’\-]\p{L}+)*[.!?]?\s*$"#, options: .regularExpression) != nil {
            return "short_word_on_release"
        }
        if duration <= 3, windows.count >= 3, windows.allSatisfy({ $0.confidence >= 0.75 }) {
            return "consistent_soft_speech_on_release"
        }
        guard held.sustained, let end = held.lastEnd, duration - end <= 3 else { return nil }
        var previous: Int?
        var quietCredit = 0.0
        for i in windows.indices where windows[i].confidence >= 0.75 {
            let start = windows[i].start
            if let last = previous {
                let gap = start - windows[last].end
                if gap > 3 {
                    guard gap <= 6, last > 0, i + 1 < windows.count,
                          supportedPair(last - 1, last), supportedPair(i, i + 1),
                          windows[(last + 1)..<i].allSatisfy({ $0.confidence <= 0.3 }),
                          Self.quietPCM(frames, from: windows[last].end, to: start) else { return nil }
                    quietCredit += gap - 3
                }
            } else if start > 3 { return nil }
            previous = i
        }
        guard quietCredit > 0, duration - held.seconds - quietCredit <= held.seconds + 3 else { return nil }
        return "verified_interior_pause_on_release"
    }

    private func supportedPair(_ left: Int, _ right: Int) -> Bool {
        let a = windows[left].confidence, b = windows[right].confidence
        return min(a, b) >= 0.75 && max(a, b) >= 0.8
    }

    private static func quietPCM(_ frames: [AudioFrame], from start: Double, to end: Double) -> Bool {
        let first = Int(ceil(start * AudioTools.rate)), last = Int(end * AudioTools.rate)
        guard first < last, (last - 1) / AudioTools.frameCount < frames.count else { return false }
        for slot in (first / AudioTools.frameCount)...((last - 1) / AudioTools.frameCount) {
            let offset = slot * AudioTools.frameCount, samples = frames[slot].samples
            let lower = max(0, first - offset), upper = min(AudioTools.frameCount, last - offset)
            guard upper <= samples.count, samples[lower..<upper].allSatisfy({ abs($0) <= 0.002 }) else { return false }
        }
        return true
    }

    public func deliveryBlock(held useHeld: Bool) -> String {
        if failed { return "analysis_failed" }
        if !completed { return "incomplete" }
        let coverage = useHeld ? held : standard
        if !coverage.sustained { return "no_sustained_speech" }
        if coverage.longestGap(through: duration) > 3 { return "long_unqualified_gap" }
        // A physical hold can include more pauses between phrases. It still
        // requires sustained speech and the same maximum gap throughout the clip.
        let pauseAllowance = useHeld ? 3.0 : 2.0
        if max(0, duration - coverage.seconds) > coverage.seconds + pauseAllowance {
            return "insufficient_coverage"
        }
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
        windows.append(Window(start: start, end: end, confidence: confidence))
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
