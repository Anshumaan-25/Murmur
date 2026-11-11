import Foundation

public enum DeliveryReason: String, Codable, Sendable {
    case ready, accessibility, targetChanged, cursorChanged, textChanged, unreadable, shortcutHeld, protectedField, clipboardChanged
    public var explanation: String {
        switch self {
        case .ready: return "Paste sent · use Copy Previous Text if needed"
        case .accessibility: return "Text ready — enable Accessibility for automatic insertion"
        case .targetChanged: return "Text ready — the focused field changed"
        case .cursorChanged: return "Text ready — the cursor moved while processing"
        case .textChanged: return "Text ready — the destination text changed"
        case .unreadable: return "Text ready — this app did not expose a text destination"
        case .shortcutHeld: return "Text ready — release the shortcut keys before insertion"
        case .clipboardChanged: return "Text ready — the clipboard changed"
        case .protectedField: return "Protected fields cannot receive dictation"
        }
    }
}
public struct FocusEvidence: Sendable {
    public var pid: Int32
    public var editable: Bool
    public var protected: Bool
    public var role: String
    public var text: String?
    public var selection: NSRange?
    public var selectedText: String
    public init(pid: Int32, editable: Bool, protected: Bool = false, role: String = "", text: String? = nil, selection: NSRange? = nil, selectedText: String = "") {
        self.pid = pid; self.editable = editable; self.protected = protected; self.role = role; self.text = text; self.selection = selection; self.selectedText = selectedText
    }
}
public enum DeliveryPolicy {
    /// During startup only, an app may expose an editor after its accessibility tree loads.
    public static func canResolveEditor(original: FocusEvidence, current: FocusEvidence,
                                        sameWindow: Bool, trackedUnchangedFocus: Bool) -> Bool {
        !original.editable && current.editable && !original.protected && !current.protected
            && original.pid > 0 && original.pid == current.pid && sameWindow && trackedUnchangedFocus
    }


    public static func decide(original: FocusEvidence, current: FocusEvidence, sameElement: Bool, sameWindow: Bool = true, trusted: Bool, requireSelection: Bool = false, focusChanged: Bool = false) -> DeliveryReason {
        guard !original.protected, !current.protected else { return .protectedField }
        guard trusted else { return .accessibility }
        guard original.pid > 0, original.pid == current.pid, sameWindow, !focusChanged else { return .targetChanged }
        guard original.editable, current.editable else { return .unreadable }
        guard sameElement else { return .targetChanged }
        if let range = original.selection, range != current.selection { return .cursorChanged }
        if let text = original.text, text != current.text { return .textChanged }
        if requireSelection {
            guard let range = original.selection, range.location >= 0, range.location != NSNotFound,
                  range.length > 0, range.length <= Int.max - range.location,
                  range.length == original.selectedText.utf16.count,
                  original.text.map({ range.location + range.length <= $0.utf16.count }) != false else { return .unreadable }
            guard original.selectedText.utf16.elementsEqual(current.selectedText.utf16) else { return .textChanged }
        }
        return .ready
    }
}
