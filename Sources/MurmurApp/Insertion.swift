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
        let focusedWindow = ownedElement(attribute(root, kAXFocusedWindowAttribute), pid: pid)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        let sources = [root, system] + (focusedWindow.map { [$0] } ?? [])
        var element: AXUIElement?
        for source in sources {
            if let candidate = ownedElement(attribute(source, kAXFocusedUIElementAttribute), pid: pid) {
                element = candidate
                break
            }
        }
        if let element { AXUIElementSetMessagingTimeout(element, 0.1) }
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String } ?? ""
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        var selectedSettable = DarwinBoolean(false)
        if let element { _ = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedSettable) }
        let editable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || selectedSettable.boolValue || (element.flatMap { attribute($0, "AXEditable") as? Bool } ?? false)
        let secured = IsSecureEventInputEnabled() || subrole == kAXSecureTextFieldSubrole || (element.flatMap { attribute($0, "AXProtectedContent") as? Bool } ?? false)
        let editorWindow = ownedElement(element.flatMap { attribute($0, kAXWindowAttribute) }, pid: pid)
        // During a window switch AX can briefly return the previous window's editor.
        let windowConsistent = focusedWindow.flatMap { window in editorWindow.map { CFEqual(window, $0) } } ?? true
        let enabled = element.flatMap { attribute($0, kAXEnabledAttribute) as? Bool } != false
        let acceptsText = windowConsistent && enabled && editable
        var range: CFRange?
        if !secured, acceptsText, let element, let ref = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            let ax = unsafeBitCast(ref, to: AXValue.self); var result = CFRange()
            if AXValueGetType(ax) == .cfRange && AXValueGetValue(ax, .cfRange, &result) { range = result }
        }
        return Destination(pid: pid, bundle: app?.bundleIdentifier ?? "", element: element,
                           windowElement: focusedWindow ?? editorWindow,
                           value: secured || !acceptsText ? nil : element.flatMap { attribute($0, kAXValueAttribute) as? String },
                           selection: range,
                           selectedText: secured || !acceptsText ? "" : element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "",
                           protected: secured, editable: acceptsText, role: role)
    }
    private static func ownedElement(_ ref: CFTypeRef?, pid: pid_t) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(ref, to: AXUIElement.self)
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }

    @MainActor func resolveEditor(continuity: FocusContinuity?) async -> Destination {
        let containerRoles = ["", "AXApplication", "AXWindow", "AXGroup", "AXWebArea", "AXScrollArea", "AXUnknown"]
        guard !Task.isCancelled, !editable, !protected, containerRoles.contains(role),
              pid > 0, let windowElement, let continuity, continuity.pid == pid,
              continuity.available, !continuity.invalidated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return self }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        // WebKit and Chromium hosts can build their editor tree on demand.
        // Try the app's existing accessibility mode before requesting enhanced mode.
        let manual = requestAccessibility("AXManualAccessibility", app: app)
        let enhanced = manual ? false : requestAccessibility("AXEnhancedUserInterface", app: app)
        let waits = manual || enhanced ? [0, 70, 100, 150, 180] : [0]
        for wait in waits {
            if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
            guard !Task.isCancelled, !continuity.invalidated, continuity.available,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return self }
            let current = Self.capture()
            guard current.pid == pid else { return self }
            if current.protected { return current }
            guard let currentWindow = current.windowElement else { continue }
            guard CFEqual(windowElement, currentWindow) else { return self }
            if DeliveryPolicy.canResolveEditor(original: evidence, current: current.evidence,
                                                sameWindow: true, trackedUnchangedFocus: !continuity.invalidated) {
                return current
            }
            guard containerRoles.contains(current.role) else { return self }
        }
        return self
    }

    private func requestAccessibility(_ key: String, app: AXUIElement) -> Bool {
        if Self.attribute(app, key) as? Bool == true { return true }
        let status = AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanTrue)
        return status == .success || Self.attribute(app, key) as? Bool == true
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

    /// Structural metadata only: never exports values, titles, selected text or identifiers.
    static func focusDiagnostics() -> [String: Any] {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        let window = ownedElement(attribute(app, kAXFocusedWindowAttribute), pid: pid)
        var result: [String: Any] = [:]
        for (name, source) in [("app", app), ("system", system)] + (window.map { [("window", $0)] } ?? []) {
            var value: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(source, kAXFocusedUIElementAttribute as CFString, &value)
            result[name + "_focus_error"] = code.rawValue
            result[name + "_focus_role"] = ownedElement(value, pid: pid).flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        }
        if let window { result["full_screen"] = attribute(window, "AXFullScreen") as? Bool ?? false }
        for key in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            result[key] = attribute(app, key) as? Bool ?? false
        }
        return result
    }
}

@MainActor final class ClipboardInserter {
    enum Outcome: String { case queued, available }
    private struct DeliveryBlocked: Error {}
    private let clipboard: ClipboardDelivery

    init(clipboard: ClipboardDelivery? = nil) {
        self.clipboard = clipboard ?? ClipboardDelivery()
    }
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
