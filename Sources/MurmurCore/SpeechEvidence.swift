import Foundation

/// Classifier evidence, never inferred from volume or decoder text. Uncertain
/// audio is still decoded and can be reviewed; it cannot authorize automatic edits.
public struct SpeechEvidence: Sendable {
    public private(set) var analyzedThrough: Double = 0
    public private(set) var lastSpeechEnd: Double?
    private var lastUncertainEnd: Double = 0
    private var consecutive = 0
    private var sustained = false
    private var failed = false
    private var completed = false
    public init() {}
    public var heardSpeech: Bool { !failed && lastSpeechEnd != nil }
    public var silence: Double { heardSpeech ? max(0, analyzedThrough - max(lastSpeechEnd ?? 0, lastUncertainEnd)) : 0 }
    public var allowsAutomaticDelivery: Bool { completed && !failed && sustained }
    public mutating func observe(start: Double, end: Double, confidence: Double) {
        guard !failed, !completed else { return }
        guard start.isFinite, end.isFinite, confidence.isFinite, start >= 0,
              end > start, end > analyzedThrough, start <= analyzedThrough, (0...1).contains(confidence) else { fail(); return }
        let adjacent = start <= analyzedThrough
        analyzedThrough = end
        if confidence >= 0.8 {
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
    public mutating func complete() { completed = true }
    public mutating func fail() { failed = true }
}
