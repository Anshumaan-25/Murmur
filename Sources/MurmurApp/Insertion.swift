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
    let editable: Bool
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }; return result
    }
    static func capture() -> Destination {
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier ?? 0
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.1)
        var element: AXUIElement?
        if let ref = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() { element = unsafeBitCast(ref, to: AXUIElement.self) }
        if let element { AXUIElementSetMessagingTimeout(element, 0.1) }
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String } ?? ""
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        let editable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || (element.flatMap { attribute($0, "AXEditable") as? Bool } ?? false)
        let secured = IsSecureEventInputEnabled() || subrole == kAXSecureTextFieldSubrole || (element.flatMap { attribute($0, "AXProtectedContent") as? Bool } ?? false)
        var range: CFRange?
        if !secured, let element, let ref = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            let ax = unsafeBitCast(ref, to: AXValue.self); var result = CFRange()
            if AXValueGetType(ax) == .cfRange && AXValueGetValue(ax, .cfRange, &result) { range = result }
        }
        return Destination(pid: pid, bundle: app?.bundleIdentifier ?? "", element: element, value: secured ? nil : element.flatMap { attribute($0, kAXValueAttribute) as? String }, selection: range, selectedText: secured ? "" : element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "", protected: secured, editable: editable)
    }
    func sameControl(as current: Destination) -> Bool {
        guard !protected, !current.protected, editable, current.editable, pid == current.pid, let element, let other = current.element else { return false }
        return CFEqual(element, other)
    }
    func matches(_ current: Destination, requireSelection: Bool = false) -> Bool {
        guard sameControl(as: current) else { return false }
        if let selection, let now = current.selection, (selection.location != now.location || selection.length != now.length) { return false }
        if let value, let now = current.value, value != now { return false }
        return !requireSelection || selectedText == current.selectedText
    }
}
@MainActor final class ClipboardInserter {
    enum Outcome: String { case inserted, copied }
    private let clipboard = ClipboardDelivery()
    func insert(_ text: String, destination: Destination, delay: Double = 0.35, pressReturn: Bool = false, requireSelection: Bool = false) async throws -> Outcome {
        clipboard.finish()
        let current = Destination.capture()
        guard !destination.protected, !current.protected else { throw MurmurError.protectedTarget }
        guard AXIsProcessTrusted(), destination.matches(current, requireSelection: requireSelection) else {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); return .copied
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { throw MurmurError.unavailable("Cannot create a paste event.") }
        try await clipboard.deliver(text, delay: delay) {
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
        if pressReturn, !Task.isCancelled, destination.sameControl(as: Destination.capture()), !IsSecureEventInputEnabled() {
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
        }
        return .inserted
    }
    func finishRestoration() { clipboard.finish() }
}
