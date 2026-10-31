import Foundation

public enum RecordingPolicy {
    public static func shouldFinish(duration: Double, silence: Double, heardSpeech: Bool, handsFree: Bool, silenceLimit: Double, maximum: Double) -> Bool {
        duration >= max(1, maximum) || (handsFree && heardSpeech && silence >= max(0.3, silenceLimit))
    }
    public static func returnIntent(_ text: String, enabled: Bool) -> (text: String, pressReturn: Bool) {
        guard enabled else { return (text, false) }
        let expression = #"(?i)[,\s]*\bpress enter[.!?\s]*$"#
        guard text.range(of: expression, options: .regularExpression) != nil else { return (text, false) }
        return (text.replacingOccurrences(of: expression, with: "", options: .regularExpression), true)
    }
}
