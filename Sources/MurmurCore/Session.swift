import Foundation

public enum CapturePhase: String, Codable, Sendable { case idle, starting, listening, processing, inserting, cancelled, failed }
public struct SessionGate: Sendable {
    public private(set) var id: UUID?
    public private(set) var phase: CapturePhase = .idle
    public init() {}
    public var canStart: Bool { [.idle, .cancelled, .failed].contains(phase) }
    @discardableResult public mutating func prepare() -> UUID {
        let fresh = UUID(); id = fresh; phase = .starting; return fresh
    }
    @discardableResult public mutating func begin() -> UUID {
        let fresh = UUID(); id = fresh; phase = .listening; return fresh
    }
    public mutating func transition(_ next: CapturePhase, session: UUID) -> Bool {
        guard id == session else { return false }
        let allowed: Bool
        switch (phase, next) {
        case (.starting, .listening), (.starting, .processing), (.listening, .processing), (.processing, .inserting), (.inserting, .idle), (_, .failed): allowed = true
        default: allowed = false
        }
        guard allowed else { return false }; phase = next; return true
    }
    public func accepts(_ candidate: UUID) -> Bool { id == candidate && phase != .cancelled && phase != .failed && phase != .idle }
    public mutating func cancel() { id = nil; phase = .cancelled }
    public mutating func reset() { id = nil; phase = .idle }
}
public enum MurmurError: LocalizedError {
    case unavailable(String), invalidAudio, empty, protectedTarget, unsupportedCommand, deadline
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .invalidAudio: return "No usable microphone samples were captured."
        case .empty: return "No speech was detected."
        case .protectedTarget: return "Protected text fields cannot receive dictation."
        case .unsupportedCommand: return "Try shorten, uppercase, lowercase, or a tone change."
        case .deadline: return "The local model exceeded its time budget."
        }
    }
}
