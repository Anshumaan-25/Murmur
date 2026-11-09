import Foundation

public enum RecordingPolicy {
    public static func sampleLimit(seconds: Double) -> Int {
        let bounded = seconds.isFinite ? min(600, max(1, seconds)) : 120
        return Int(bounded * AudioTools.rate)
    }

    public static func shouldFinish(duration: Double, silence: Double, heardSpeech: Bool, handsFree: Bool, silenceLimit: Double, maximum: Double, holdToTalk: Bool = false) -> Bool {
        duration >= max(1, maximum) || (!holdToTalk && handsFree && heardSpeech && silence >= max(0.3, silenceLimit))
    }
}
