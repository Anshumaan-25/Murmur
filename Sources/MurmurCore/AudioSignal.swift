import Foundation

public enum AudioSignal: String, Sendable {
    case noInput, silent, quiet, active, clipped
    public static func classify(rms: Float, peak: Float, received: Bool) -> Self {
        guard received else { return .noInput }
        if peak >= 0.99 { return .clipped }
        if rms <= 0 { return .silent }
        return rms < 0.008 ? .quiet : .active
    }
    public var message: String {
        switch self {
        case .noInput: return "Waiting for microphone samples…"
        case .silent: return "Listening · no sound yet"
        case .quiet: return "Listening · input is quiet"
        case .active: return "Listening…"
        case .clipped: return "Listening · move away from the microphone"
        }
    }
}

/// Meter feedback only. Recognition and hands-free stopping use their own evidence.
public struct ListeningFeedback: Sendable {
    private var quietSince: TimeInterval?
    public init() {}

    public mutating func update(_ signal: AudioSignal, at time: TimeInterval) -> AudioSignal {
        switch signal {
        case .quiet, .silent:
            if quietSince == nil { quietSince = time }
            return time - (quietSince ?? time) >= 2 ? .quiet : .active
        default:
            quietSince = nil
            return signal
        }
    }
}
