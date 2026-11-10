import Foundation

/// Classifier evidence, never inferred from volume or decoder text. Uncertain
/// audio is still decoded and can be reviewed; it cannot authorize automatic edits.
public struct SpeechEvidence: Sendable {
    public private(set) var analyzedThrough: Double = 0
    public private(set) var lastSpeechEnd: Double?
    public private(set) var speechSeconds: Double = 0
    private var longestClosedGap: Double = 0
    private var completedDuration: Double = 0
    private var lastUncertainEnd: Double = 0
    private var consecutive = 0
    private var sustained = false
    private var failed = false
    private var completed = false
    public init() {}
    public var heardSpeech: Bool { !failed && lastSpeechEnd != nil }
    public var silence: Double { heardSpeech ? max(0, analyzedThrough - max(lastSpeechEnd ?? 0, lastUncertainEnd)) : 0 }
    private var duration: Double { completed ? completedDuration : analyzedThrough }
    public var unqualifiedSeconds: Double { max(0, duration - speechSeconds) }
    public var longestUnqualifiedSpan: Double { max(longestClosedGap, duration - (lastSpeechEnd ?? 0)) }
    public var allowsAutomaticDelivery: Bool {
        // Speech somewhere cannot authorize an entire noisy recording. Preserve
        // ordinary pauses, but review long gaps or mostly unqualified audio.
        completed && !failed && sustained && longestUnqualifiedSpan <= 3 && unqualifiedSeconds <= speechSeconds + 2
    }
    public mutating func observe(start: Double, end: Double, confidence: Double) {
        guard !failed, !completed else { return }
        guard start.isFinite, end.isFinite, confidence.isFinite, start >= 0,
              end > start, end > analyzedThrough, start <= analyzedThrough, (0...1).contains(confidence) else { fail(); return }
        let adjacent = start <= analyzedThrough
        analyzedThrough = end
        if confidence >= 0.8 {
            let previousEnd = lastSpeechEnd ?? 0
            longestClosedGap = max(longestClosedGap, start - previousEnd)
            // Union of overlapping qualified windows, never a sum that double
            // counts overlap. Prefix, interior and trailing gaps all contribute.
            speechSeconds += end - max(start, previousEnd)
            lastSpeechEnd = end
            consecutive = adjacent ? consecutive + 1 : 1
            if consecutive >= 2 { sustained = true }
        } else {
            consecutive = 0
            // Version-1 reports about 0.204 speech confidence for digital silence
            // on the qualification fixture. Keep a margin, while treating the
            // intermediate band conservatively instead of claiming it is silence.
            if confidence > 0.3 { lastUncertainEnd = end }
        }
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
}
