import Foundation

/// Energy-based fallback, not a semantic speech classifier. Audio retention is independent.
/// Measure a short baseline, then require energy above it to advance the silence clock.
public struct SpeechActivity {
    private var started: Double?
    private var floor: Float = 1
    public private(set) var lastVoice: Double?
    public init() {}
    @discardableResult public mutating func observe(rms: Float, uptime: Double) -> Bool {
        guard rms.isFinite, rms >= 0, uptime.isFinite else { return false }
        if started == nil { started = uptime }
        if uptime - (started ?? uptime) < 0.3 {
            floor = min(floor, rms)
            return false
        }
        let threshold = max(0.001, floor * 3)
        if rms > threshold { lastVoice = uptime; return true }
        // Falling background levels lower the baseline; sustained speech cannot raise it.
        floor = min(floor, rms)
        return false
    }
}
