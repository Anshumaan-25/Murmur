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
        for source in [root, system] {
            if let ref = attribute(source, kAXFocusedUIElementAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() {
                let candidate = unsafeBitCast(ref, to: AXUIElement.self); var owner: pid_t = 0
                if AXUIElementGetPid(candidate, &owner) == .success && owner == pid { element = candidate; break }
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
        var windowElement: AXUIElement?
        if let ref = element.flatMap({ attribute($0, kAXWindowAttribute) }) ?? attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() { windowElement = unsafeBitCast(ref, to: AXUIElement.self) }
        return Destination(pid: pid, bundle: app?.bundleIdentifier ?? "", element: element, windowElement: windowElement, value: secured ? nil : element.flatMap { attribute($0, kAXValueAttribute) as? String }, selection: range, selectedText: secured ? "" : element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "", protected: secured, editable: editable, role: role)
    }
    var screenPoint: NSPoint? {
        guard let windowElement,
              let position = Self.attribute(windowElement, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = Self.attribute(windowElement, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions),
              let originScreen = NSScreen.screens.first else { return nil }
        return NSPoint(x: point.x + dimensions.width / 2, y: originScreen.frame.maxY - point.y - dimensions.height / 2)
    }
    var evidence: FocusEvidence {
        FocusEvidence(pid: pid, editable: editable, protected: protected, role: role, text: value, selection: selection.map { NSRange(location: $0.location, length: $0.length) }, selectedText: selectedText)
    }
    func reason(comparedTo current: Destination, requireSelection: Bool = false, focusChanged: Bool = false) -> DeliveryReason {
        let equal = element.flatMap { a in current.element.map { CFEqual(a, $0) } } ?? false
        let sameWindow = windowElement.flatMap { a in current.windowElement.map { CFEqual(a, $0) } } ?? false
        return DeliveryPolicy.decide(original: evidence, current: current.evidence, sameElement: equal, sameWindow: sameWindow, trusted: AXIsProcessTrusted() && CGPreflightPostEventAccess(), requireSelection: requireSelection, focusChanged: focusChanged)
    }
    var diagnostic: [String:Any] {
        ["app":bundle, "role":role, "has_element":element != nil, "editable":editable, "protected":protected, "has_selection":selection != nil, "has_value":value != nil, "has_window":windowElement != nil]
    }
}

@MainActor final class ClipboardInserter {
    enum Outcome: String { case queued, available }
    private struct DeliveryBlocked: Error {}
    private let clipboard = ClipboardDelivery()
    private(set) var lastReason = DeliveryReason.ready
    private(set) var lastAttempt: [String:Any] = [:]

    func insert(_ text: String, destination: Destination, delay: Double = 0.35, requireSelection: Bool = false, continuity: FocusContinuity? = nil) async throws -> Outcome {
        try Task.checkCancellation()
        clipboard.finish()
        func checkDestination() throws {
            let current = Destination.capture()
            let changed = continuity.map { $0.pid != destination.pid || $0.invalidated } ?? false
            lastReason = destination.reason(comparedTo: current, requireSelection: requireSelection, focusChanged: changed)
            lastAttempt = ["original":destination.diagnostic, "current":current.diagnostic, "reason":lastReason.rawValue, "focus_tracking_available":continuity?.available ?? false, "focus_unchanged":!changed]
            if lastReason == .protectedField { throw MurmurError.protectedTarget }
            if lastReason != .ready { throw DeliveryBlocked() }
        }
        do {
            try checkDestination()
            let until = ProcessInfo.processInfo.systemUptime + 1.2
            while [58, 59, 61, 62].contains(where: { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }) {
                if ProcessInfo.processInfo.systemUptime >= until { lastReason = .shortcutHeld; return .available }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let source = CGEventSource(stateID: .privateState)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                throw MurmurError.unavailable("Cannot create a paste event.")
            }
            try await clipboard.deliver(text, delay: delay, validate: checkDestination) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid,
                      !IsSecureEventInputEnabled() else {
                    lastReason = .targetChanged
                    throw DeliveryBlocked()
                }
                down.flags = .maskCommand; up.flags = []
                down.postToPid(destination.pid); up.postToPid(destination.pid)
            }
            return .queued
        } catch is DeliveryBlocked {
            return .available
        } catch is ClipboardDelivery.Changed {
            lastReason = .clipboardChanged
            return .available
        }
    }

    func finishRestoration() { clipboard.finish() }
}
