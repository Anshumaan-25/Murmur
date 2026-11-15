import AppKit
import ApplicationServices
import Carbon
import Darwin
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
    private static let containers = ["", "AXApplication", "AXWindow", "AXGroup", "AXWebArea", "AXScrollArea", "AXUnknown"]
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }; return result
    }
    static func canSetSelectedText(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
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
        var pendingSources = sources[...]
        var element: AXUIElement?
        while let source = pendingSources.popFirst() {
            if let candidate = ownedElement(attribute(source, kAXFocusedUIElementAttribute), pid: pid) {
                element = candidate
                break
            }
        }
        if let container = element, let focusedWindow,
           containers.contains(attribute(container, kAXRoleAttribute) as? String ?? "") {
            // The app and system can report different levels of the same web
            // focus tree. Use another source only if it confirms a focused editor
            // in the same window. A page container alone cannot receive a paste.
            let alternate = (Array(pendingSources) + [container]).compactMap {
                ownedElement(attribute($0, kAXFocusedUIElementAttribute), pid: pid)
            }
            if let focusedEditor = alternate.first(where: { candidate in
                guard editableRole(candidate), attribute(candidate, kAXFocusedAttribute) as? Bool == true,
                      let window = ownedElement(attribute(candidate, kAXWindowAttribute), pid: pid) else { return false }
                return CFEqual(window, focusedWindow)
            }) { element = focusedEditor }
        }
        if let element { AXUIElementSetMessagingTimeout(element, 0.1) }
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String } ?? ""
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        let editable = element.map { editableRole($0, role: role) } ?? false
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

    private static func editableRole(_ element: AXUIElement, role: String? = nil) -> Bool {
        [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? (attribute(element, kAXRoleAttribute) as? String ?? ""))
            || canSetSelectedText(element) || attribute(element, "AXEditable") as? Bool == true
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
        guard !Task.isCancelled, !editable, !protected, Self.containers.contains(role),
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
        let waits = manual || enhanced ? [0, 70, 100, 150, 180, 250] : [0, 50, 100, 160]
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
            guard Self.containers.contains(current.role) else { return self }
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
        return DeliveryPolicy.decide(original: evidence, current: current.evidence, sameElement: equal, sameWindow: sameWindow, trusted: AXIsProcessTrusted(), requireSelection: requireSelection, focusChanged: focusChanged)
    }

    var hasWritableSelection: Bool {
        element.map { Self.canSetSelectedText($0) || WebTextReplacement.isSupported(by: $0) } == true
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

// WebKit can acknowledge AXSelectedText without changing the editor. Its
// text operation uses a range tied to the document instead of the responder.
private enum WebTextReplacement {
    private static let attribute = "AXTextOperation"
    private typealias RangeType = @convention(c) () -> CFTypeID
    private typealias CopyMarker = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?

    static func isSupported(by field: AXUIElement) -> Bool {
        var attributes: CFArray?
        return AXUIElementCopyParameterizedAttributeNames(field, &attributes) == .success
            && (attributes as? [String])?.contains(attribute) == true
    }

    static func selection(in field: AXUIElement, selectedText: String, length: Int) -> CFTypeRef? {
        // These marker accessors are optional on the host. Without both
        // endpoints we cannot establish that the range belongs to this field.
        let symbols = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let type = dlsym(symbols, "AXTextMarkerRangeGetTypeID"),
              let start = dlsym(symbols, "AXTextMarkerRangeCopyStartMarker"),
              let end = dlsym(symbols, "AXTextMarkerRangeCopyEndMarker"),
              let range = Destination.attribute(field, "AXSelectedTextMarkerRange"),
              CFGetTypeID(range) == unsafeBitCast(type, to: RangeType.self)() else { return nil }
        for accessor in [start, end] {
            guard let marker = unsafeBitCast(accessor, to: CopyMarker.self)(range)?.takeRetainedValue(),
                  isInside(field, marker: marker) else { return nil }
        }
        guard (parameter("AXLengthForTextMarkerRange", in: field, value: range) as? Int) == length else { return nil }
        if length != 0 {
            guard let actual = parameter("AXStringForTextMarkerRange", in: field, value: range) as? String,
                  actual.utf16.elementsEqual(selectedText.utf16) else { return nil }
        }
        return range
    }

    private static func isInside(_ field: AXUIElement, marker: CFTypeRef) -> Bool {
        var ancestor = parameter("AXUIElementForTextMarker", in: field, value: marker)
        for _ in 0..<12 {
            guard let node = ancestor, CFGetTypeID(node) == AXUIElementGetTypeID() else { return false }
            if CFEqual(node, field) { return true }
            let element = unsafeBitCast(node, to: AXUIElement.self)
            let role = Destination.attribute(element, kAXRoleAttribute) as? String
            if role == kAXTextAreaRole || role == kAXTextFieldRole || role == "AXWebArea" { return false }
            ancestor = Destination.attribute(element, kAXParentAttribute)
        }
        return false
    }

    private static func parameter(_ name: String, in field: AXUIElement, value: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(field, name as CFString, value, &result) == .success ? result : nil
    }

    static func replace(in field: AXUIElement, range: CFTypeRef, with text: String) -> AXError {
        let request: NSDictionary = ["AXTextOperationType": "TextOperationReplacePreserveCase",
                                     "AXTextOperationMarkerRanges": [range],
                                     "AXTextOperationReplacementString": text,
                                     "AXTextOperationSmartReplace": false]
        var result: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(field, attribute as CFString, request, &result)
    }
}

@MainActor final class TextInserter {
    enum Outcome: String { case inserted, available, unconfirmed }
    private struct PasteBlocked: Error {}
    private let clipboard = ClipboardDelivery()
    private(set) var lastReason = DeliveryReason.ready
    private(set) var lastAttempt: [String:Any] = [:]

    func insert(_ text: String, destination: Destination, requireSelection: Bool = false,
                continuity: FocusContinuity? = nil, clipboardDelay: Double = 0.35) async throws -> Outcome {
        try Task.checkCancellation()
        let current = Destination.capture()
        let changed = continuity.map { $0.pid != destination.pid || $0.invalidated } ?? false
        lastReason = destination.reason(comparedTo: current, requireSelection: requireSelection, focusChanged: changed)
        lastAttempt = ["original": destination.diagnostic, "current": current.diagnostic,
                       "focus_tracking_available": continuity?.available ?? false, "focus_unchanged": !changed]
        defer { lastAttempt["reason"] = lastReason.rawValue }
        if lastReason == .protectedField { throw MurmurError.protectedTarget }
        guard lastReason == .ready else { return .available }
        guard let element = destination.element,
              let expected = destination.evidence.replacingSelection(with: text),
              let currentExpected = current.evidence.replacingSelection(with: text) else {
            lastReason = .insertionUnsupported
            return .available
        }
        guard expected.utf16.elementsEqual(currentExpected.utf16) else {
            lastReason = .textChanged
            return .available
        }
        // Ordinary dictation uses the editor's native Paste command. Web
        // composers can acknowledge an AX write and discard the actual edit.
        if !requireSelection, expected != current.value, let continuity, continuity.available, CGPreflightPostEventAccess() {
            do {
                return try await paste(text, into: destination, element: element, expected: expected,
                                       continuity: continuity, delay: clipboardDelay)
            } catch is PasteboardSnapshot.Unrestorable {
                // The native Paste command was never sent. Direct insertion
                // can still work when the clipboard contains a protected item.
                lastReason = .clipboardUnrestorable
            }
        }
        let webRange: CFTypeRef?
        if WebTextReplacement.isSupported(by: element) {
            guard let length = current.selection?.length,
                  let range = WebTextReplacement.selection(in: element, selectedText: current.selectedText, length: length) else {
                lastReason = .insertionUnsupported
                return .available
            }
            webRange = range
        } else {
            guard Destination.canSetSelectedText(element) else {
                lastReason = .insertionUnsupported
                return .available
            }
            webRange = nil
        }
        // Marker discovery can require several AX round trips. Recheck the
        // original field and selection immediately before the single write.
        let final = Destination.capture()
        lastReason = destination.reason(comparedTo: final, requireSelection: requireSelection, focusChanged: continuity?.invalidated == true)
        lastAttempt["current"] = final.diagnostic
        if lastReason == .protectedField { throw MurmurError.protectedTarget }
        guard lastReason == .ready else { return .available }
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid,
              continuity?.invalidated != true else {
            lastReason = .targetChanged
            return .available
        }
        guard !IsSecureEventInputEnabled() else {
            lastReason = .protectedField
            throw MurmurError.protectedTarget
        }

        // Send the replacement to the captured AX element, never to the app's current responder.
        lastAttempt["method"] = webRange == nil ? "selected_text" : "web_text_operation"
        let status = webRange.map { WebTextReplacement.replace(in: element, range: $0, with: text) }
            ?? AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        lastAttempt["ax_status"] = status.rawValue
        switch status {
        case .success:
            let deadline = ContinuousClock.now + .milliseconds(400)
            while NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid,
                  continuity?.invalidated != true, !IsSecureEventInputEnabled() {
                try Task.checkCancellation()
                if let value = Destination.attribute(element, kAXValueAttribute) as? String,
                   value.utf16.elementsEqual(expected.utf16) {
                    lastReason = .inserted
                    return .inserted
                }
                guard ContinuousClock.now < deadline else { break }
                try await Task.sleep(for: .milliseconds(40))
            }
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .notImplemented, .illegalArgument:
            lastReason = .insertionUnsupported
            return .available
        case .invalidUIElement:
            lastReason = .targetChanged
            return .available
        default:
            break
        }
        // A timed-out request or an editor that transforms text may already have applied the edit.
        lastReason = .insertionUnconfirmed
        return .unconfirmed
    }

    func finish() { clipboard.finish() }

    private func paste(_ text: String, into destination: Destination, element: AXUIElement,
                       expected: String, continuity: FocusContinuity, delay: Double) async throws -> Outcome {
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            lastReason = .insertionUnsupported
            return .available
        }
        let deadline = ContinuousClock.now + .seconds(1)
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        func modifiersReleased() -> Bool {
            CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
        }
        func validate() throws {
            let current = Destination.capture()
            let changed = !continuity.available || continuity.invalidated || continuity.pid != destination.pid
            lastAttempt["current"] = current.diagnostic
            lastAttempt["focus_unchanged"] = !changed
            lastReason = destination.reason(comparedTo: current, focusChanged: changed)
            if lastReason == .protectedField { throw MurmurError.protectedTarget }
            guard lastReason == .ready else { throw PasteBlocked() }
            guard current.evidence.replacingSelection(with: text)?.utf16.elementsEqual(expected.utf16) == true else {
                lastReason = .textChanged
                throw PasteBlocked()
            }
            guard modifiersReleased() else {
                lastReason = .shortcutHeld
                throw PasteBlocked()
            }
        }
        while !modifiersReleased() {
            guard ContinuousClock.now < deadline && !continuity.invalidated else {
                lastReason = continuity.invalidated ? .targetChanged : .shortcutHeld
                return .available
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        do {
            try validate()
            down.flags = .maskCommand
            up.flags = []
            let inserted = try await clipboard.deliver(text, delay: delay, validate: validate, verifyPaste: {
                guard !IsSecureEventInputEnabled() else { return false }
                return (Destination.attribute(element, kAXValueAttribute) as? String) == expected
            }, keepTextIfUnconfirmed: true) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid,
                      continuity.available, !continuity.invalidated, modifiersReleased(),
                      !IsSecureEventInputEnabled() else {
                    lastReason = .targetChanged
                    throw PasteBlocked()
                }
                lastAttempt["method"] = "native_paste"
                down.postToPid(destination.pid)
                up.postToPid(destination.pid)
            }
            try Task.checkCancellation()
            lastReason = inserted ? .inserted : .insertionUnconfirmed
            return inserted ? .inserted : .unconfirmed
        } catch is PasteBlocked {
            return .available
        } catch is ClipboardDelivery.Changed {
            lastReason = .clipboardChanged
            return .available
        }
    }
}
