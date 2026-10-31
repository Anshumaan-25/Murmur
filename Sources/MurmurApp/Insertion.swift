import AppKit
import ApplicationServices
import Carbon
import MurmurCore

struct Destination {
    let pid: pid_t
    let bundle: String
    let element: AXUIElement?
    let value: String?
    let selection: CFRange?
    let selectedText: String
    let protected: Bool
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }; return result
    }
    static func capture() -> Destination {
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier ?? 0
        let root = AXUIElementCreateApplication(pid)
        var element: AXUIElement?
        if let ref = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() { element = unsafeBitCast(ref, to: AXUIElement.self) }
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String } ?? ""
        let secured = IsSecureEventInputEnabled() || subrole == kAXSecureTextFieldSubrole || (element.flatMap { attribute($0, "AXProtectedContent") as? Bool } ?? false)
        var range: CFRange?
        if !secured, let element, let ref = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            let ax = unsafeBitCast(ref, to: AXValue.self); var result = CFRange()
            if AXValueGetType(ax) == .cfRange && AXValueGetValue(ax, .cfRange, &result) { range = result }
        }
        return Destination(pid: pid, bundle: app?.bundleIdentifier ?? "", element: element, value: secured ? nil : element.flatMap { attribute($0, kAXValueAttribute) as? String }, selection: range, selectedText: secured ? "" : element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "", protected: secured)
    }
    func matches(_ current: Destination, requireSelection: Bool = false) -> Bool {
        guard !protected, !current.protected, pid == current.pid, let element, let other = current.element, CFEqual(element, other) else { return false }
        if let selection, let now = current.selection, (selection.location != now.location || selection.length != now.length) { return false }
        if let value, let now = current.value, value != now { return false }
        return !requireSelection || selectedText == current.selectedText
    }
}
@MainActor final class ClipboardInserter {
    enum Outcome: String { case inserted, copied }
    private var transaction: UUID?
    private var restoration: (() -> Void)?
    func insert(_ text: String, destination: Destination, delay: Double = 0.35, pressReturn: Bool = false, requireSelection: Bool = false) async throws -> Outcome {
        restoration?(); restoration = nil
        let current = Destination.capture()
        guard !destination.protected, !current.protected else { throw MurmurError.protectedTarget }
        guard AXIsProcessTrusted(), destination.matches(current, requireSelection: requireSelection) else {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); return .copied
        }
        let token = UUID(); transaction = token
        let board = NSPasteboard.general
        let saved = try PasteboardSnapshot(board)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { throw MurmurError.unavailable("Cannot create a paste event.") }
        board.clearContents(); board.setString(text, forType: .string)
        let offered = board.changeCount
        let restore = { if board.changeCount == offered { saved.restore(board) } }
        restoration = restore
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: UInt64(max(0.1, min(2, delay)) * 1e9))
        restore(); if transaction == token { restoration = nil; transaction = nil }
        if pressReturn, !Task.isCancelled, destination.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier, !IsSecureEventInputEnabled() {
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
        }
        return .inserted
    }
    func finishRestoration() { restoration?(); restoration = nil }
}
