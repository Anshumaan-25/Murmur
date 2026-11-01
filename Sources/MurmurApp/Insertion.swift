import AppKit
import ApplicationServices
import Carbon
import MurmurCore

struct Destination {
    let pid: pid_t
    let bundle: String
    let element: AXUIElement?
    let windowElement: AXUIElement?
    let value: String?
    let selection: CFRange?
    let selectedText: String
    let protected: Bool
    let editable: Bool
    let identifier: String?
    let bounds: [Double]?
    let role: String
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }; return result
    }
    static func capture() -> Destination {
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier ?? 0
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.1)
        var element: AXUIElement?
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.1)
        for (source, fromApplication) in [(root, true), (system, false)] {
            if let ref = attribute(source, kAXFocusedUIElementAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() {
                let candidate = unsafeBitCast(ref, to: AXUIElement.self); var owner: pid_t = 0
                if AXUIElementGetPid(candidate, &owner) == .success && (owner == pid || fromApplication) { element = candidate; break }
            }
        }
        if let element { AXUIElementSetMessagingTimeout(element, 0.1) }
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String } ?? ""
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        var selectedSettable = DarwinBoolean(false)
        if let element { _ = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedSettable) }
        let editable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || selectedSettable.boolValue || (element.flatMap { attribute($0, "AXEditable") as? Bool } ?? false)
        let secured = IsSecureEventInputEnabled() || subrole == kAXSecureTextFieldSubrole || (element.flatMap { attribute($0, "AXProtectedContent") as? Bool } ?? false)
        var range: CFRange?
        if !secured, let element, let ref = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            let ax = unsafeBitCast(ref, to: AXValue.self); var result = CFRange()
            if AXValueGetType(ax) == .cfRange && AXValueGetValue(ax, .cfRange, &result) { range = result }
        }
        let identifier = element.flatMap { attribute($0, kAXIdentifierAttribute) as? String }
        var bounds: [Double]?
        if let element, let point = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute), CFGetTypeID(point) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var p = CGPoint.zero; var s = CGSize.zero
            if AXValueGetValue(unsafeBitCast(point, to: AXValue.self), .cgPoint, &p), AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &s) { bounds = [p.x, p.y, s.width, s.height] }
        }
        var windowElement: AXUIElement?
        if let ref = element.flatMap({ attribute($0, kAXWindowAttribute) }) ?? attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() { windowElement = unsafeBitCast(ref, to: AXUIElement.self) }
        return Destination(pid: pid, bundle: app?.bundleIdentifier ?? "", element: element, windowElement: windowElement, value: secured ? nil : element.flatMap { attribute($0, kAXValueAttribute) as? String }, selection: range, selectedText: secured ? "" : element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "", protected: secured, editable: editable, identifier: identifier, bounds: bounds, role: role)
    }
    @MainActor static func prepared(_ initial: Destination? = nil) async throws -> Destination {
        let first = initial ?? capture()
        guard first.element == nil, !first.protected, AXIsProcessTrusted() else { return first }
        // Web editors can construct their accessibility focus lazily on the first query.
        for delay: UInt64 in [60_000_000, 120_000_000, 180_000_000] {
            try await Task.sleep(nanoseconds: delay); try Task.checkCancellation()
            let next = capture()
            guard next.pid == first.pid else { return first }
            if let a = first.windowElement, let b = next.windowElement, !CFEqual(a, b) { return first }
            if next.editable || next.protected { return next }
        }
        return first
    }
    func sameControl(as current: Destination) -> Bool {
        guard !protected, !current.protected, editable, current.editable, pid == current.pid, let element, let other = current.element else { return false }
        return CFEqual(element, other)
    }
    var evidence: FocusEvidence {
        FocusEvidence(pid: pid, editable: editable, protected: protected, identifier: identifier, role: role, bounds: bounds, text: value, selection: selection.map { NSRange(location: $0.location, length: $0.length) })
    }
    func reason(comparedTo current: Destination, requireSelection: Bool = false) -> DeliveryReason {
        let equal = element.flatMap { a in current.element.map { CFEqual(a, $0) } } ?? false
        let sameWindow = windowElement.flatMap { a in current.windowElement.map { CFEqual(a, $0) } } ?? true
        return DeliveryPolicy.decide(original: evidence, current: current.evidence, sameElement: equal, sameWindow: sameWindow, trusted: AXIsProcessTrusted(), requireSelection: requireSelection)
    }
    func matches(_ current: Destination, requireSelection: Bool = false) -> Bool { reason(comparedTo: current, requireSelection: requireSelection) == .ready }

}
@MainActor final class ClipboardInserter {
    enum Outcome: String { case inserted, copied }
    private let clipboard = ClipboardDelivery()
    private(set) var lastReason = DeliveryReason.ready
    private(set) var copiedChangeCount: Int?
    func insert(_ text: String, destination: Destination, delay: Double = 0.35, pressReturn: Bool = false, requireSelection: Bool = false) async throws -> Outcome {
        try Task.checkCancellation()
        clipboard.finish(); copiedChangeCount = nil
        lastReason = destination.reason(comparedTo: Destination.capture(), requireSelection: requireSelection)
        if lastReason == .protectedField { throw MurmurError.protectedTarget }
        if lastReason == .ready {
            let until = ProcessInfo.processInfo.systemUptime + 1.2
            // Wait for the trigger modifiers; a prior synthetic Cmd-V can still appear in Quartz’s Command state.
            while [58, 59, 61, 62].contains(where: { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }) {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime >= until { lastReason = .shortcutHeld; break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            if lastReason == .ready { lastReason = destination.reason(comparedTo: Destination.capture(), requireSelection: requireSelection) }
        }
        if lastReason == .protectedField { throw MurmurError.protectedTarget }
        try Task.checkCancellation()
        guard lastReason == .ready else {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copiedChangeCount = NSPasteboard.general.changeCount; return .copied
        }
        try Task.checkCancellation()
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw MurmurError.unavailable("Cannot create a paste event.") }
        try await clipboard.deliver(text, delay: delay) {
            down.flags = .maskCommand; up.flags = []
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
