import Foundation

/// Tracks focus-changing input without storing keys, text, or pointer locations.
public struct FocusActivity: Sendable {
    public private(set) var unchanged = true
    public init() {}
    public mutating func invalidate() { unchanged = false }
    public mutating func key(_ code: UInt16, dictationChord: Bool, toggleKey: UInt16, holdKey: UInt16?, standaloneHold: Bool = true) {
        if dictationChord && [toggleKey, 9, 15].contains(code) { return }
        if standaloneHold && code == holdKey { return }
        invalidate()
    }
}
