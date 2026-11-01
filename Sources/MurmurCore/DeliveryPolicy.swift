import Foundation

public enum DeliveryReason: String, Codable, Sendable {
    case ready, accessibility, targetChanged, cursorChanged, textChanged, unreadable, shortcutHeld, protectedField
    public var explanation: String {
        switch self {
        case .ready: return "Inserted into your text field"
        case .accessibility: return "Copied — enable Accessibility for automatic insertion"
        case .targetChanged: return "Copied — the focused field changed"
        case .cursorChanged: return "Copied — the cursor moved while processing"
        case .textChanged: return "Copied — the destination text changed"
        case .unreadable: return "Copied — this app did not expose a text destination"
        case .shortcutHeld: return "Copied — release the shortcut keys before insertion"
        case .protectedField: return "Protected fields cannot receive dictation"
        }
    }
}
public struct FocusEvidence: Sendable {
    public var pid: Int32
    public var editable: Bool
    public var protected: Bool
    public var identifier: String?
    public var role: String
    public var bounds: [Double]?
    public var text: String?
    public var selection: NSRange?
    public init(pid: Int32, editable: Bool, protected: Bool = false, identifier: String? = nil, role: String = "", bounds: [Double]? = nil, text: String? = nil, selection: NSRange? = nil) {
        self.pid = pid; self.editable = editable; self.protected = protected; self.identifier = identifier; self.role = role; self.bounds = bounds; self.text = text; self.selection = selection
    }
}
public enum DeliveryPolicy {
    public static func decide(original: FocusEvidence, current: FocusEvidence, sameElement: Bool, sameWindow: Bool = true, trusted: Bool, requireSelection: Bool = false) -> DeliveryReason {
        guard !original.protected, !current.protected else { return .protectedField }
        guard trusted else { return .accessibility }
        guard original.pid == current.pid else { return .targetChanged }
        guard original.editable, current.editable else { return .unreadable }
        guard sameElement || sameWindow else { return .targetChanged }
        var identity = sameElement
        if !identity, let id = original.identifier, !id.isEmpty, id == current.identifier, original.role == current.role, let a = original.bounds, let b = current.bounds, a.count == 4, b.count == 4, zip(a,b).allSatisfy({ abs($0.0 - $0.1) <= 1.5 }) { identity = true }
        if !identity, let a = original.bounds, let b = current.bounds, a.count == 4, b.count == 4, zip(a,b).allSatisfy({ abs($0.0 - $0.1) <= 1.5 }), original.role == current.role, let text = original.text, text == current.text, let selection = original.selection, selection == current.selection { identity = true }
        guard identity else { return .targetChanged }
        if let range = original.selection, let now = current.selection, range != now { return .cursorChanged }
        if requireSelection && (original.selection == nil || current.selection == nil) { return .unreadable }
        if let text = original.text, let now = current.text, text != now { return .textChanged }
        return .ready
    }
}
