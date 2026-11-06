import AppKit
import Carbon
import IOKit.hidsystem
import MurmurCore

final class Hotkeys {
    enum Shortcut: Hashable, CaseIterable {
        case toggle, pasteLast, command, cancel
    }
    private struct Registration {
        let reference: EventHotKeyRef
        let id: UInt32
        var pressed = false
    }
    private enum HoldEvent { case press, release, interrupt }

    var toggle: (() -> Void)?
    var cancel: (() -> Void)?
    var pasteLast: (() -> Void)?
    var command: (() -> Void)?
    var hold: ((Bool) -> Void)?
    var holdInterrupted: (() -> Void)?

    private static let signature: OSType = 0x4D55524D
    private static var nextRegistrationID: UInt32 = 0
    private static let holdDelay = 0.18
    private static let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn, .maskHelp]
    private var registrations: [Shortcut: Registration] = [:]
    private var handler: EventHandlerRef?
    private var toggleKeyCode: UInt32 = 49
    private var escapeRequested = false
    private var suspended = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = HoldGesture()
    private var holdKey = HoldKey.globe
    private var holdEnabled = false
    private var holdGeneration: UInt64 = 0
    private var pendingHold: UUID?
    private var deliveredHoldDown = false
    private(set) var lastTriggerUptime = ProcessInfo.processInfo.systemUptime

    var availabilityMessage: String? {
        if suspended { return "Shortcuts are paused while this Mac session is inactive." }
        if registrations[.toggle] == nil {
            return "Could not register the dictation shortcut. Choose another shortcut in Settings or start from the menu bar."
        }
        if registrations[.pasteLast] == nil || registrations[.command] == nil {
            return "A paste or editing shortcut could not be registered. Use the corresponding menu bar command."
        }
        if holdEnabled && !holdTapReady {
            if !CGPreflightListenEventAccess() { return "Enable Input Monitoring for hold-to-talk." }
            return "Hold-to-talk could not start. The toggle shortcut is available."
        }
        return nil
    }

    init() {
        refreshShortcuts()
    }

    func configure(keyCode: UInt32) {
        if keyCode != toggleKeyCode {
            toggleKeyCode = keyCode
            unregister(.toggle)
        }
        refreshShortcuts()
    }

    func escape(_ active: Bool) {
        escapeRequested = active
        if active { refreshShortcuts() }
        else { unregister(.cancel) }
    }

    func enableHold(_ enabled: Bool, key: HoldKey = .globe) {
        if holdEnabled != enabled || holdKey != key {
            holdEnabled = enabled
            holdKey = key
            removeHoldTap(notifyInterruption: !suspended)
        }
        refreshHold()
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        for shortcut in Shortcut.allCases { unregister(shortcut) }
        removeHoldTap(notifyInterruption: false)
    }

    func resume() {
        suspended = false
        refresh()
    }

    func refresh() {
        refreshShortcuts()
        refreshHold()
    }

    func eventID(for shortcut: Shortcut) -> EventHotKeyID? {
        registrations[shortcut].map { EventHotKeyID(signature: Self.signature, id: $0.id) }
    }

    private func refreshShortcuts() {
        guard !suspended else { return }
        if handler == nil { installHandler() }
        guard handler != nil else { return }
        let modifiers = UInt32(controlKey | optionKey)
        register(.toggle, key: toggleKeyCode, modifiers: modifiers)
        register(.pasteLast, key: 9, modifiers: modifiers)
        register(.command, key: 15, modifiers: modifiers)
        if escapeRequested { register(.cancel, key: 53, modifiers: 0) }
    }

    private func installHandler() {
        let specs = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == Hotkeys.signature else { return OSStatus(eventNotHandledErr) }
            return owner.handleShortcutEvent(id: identity.id, kind: GetEventKind(event), uptime: GetEventTime(event))
        }, specs.count, specs, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { handler = nil }
    }

    private func handleShortcutEvent(id: UInt32, kind: UInt32, uptime: Double) -> OSStatus {
        guard !suspended, let shortcut = registrations.first(where: { $0.value.id == id })?.key else {
            return OSStatus(eventNotHandledErr)
        }
        if kind == kEventHotKeyReleased {
            registrations[shortcut]?.pressed = false
            return noErr
        }
        guard kind == kEventHotKeyPressed else { return OSStatus(eventNotHandledErr) }
        guard registrations[shortcut]?.pressed == false else { return noErr }
        registrations[shortcut]?.pressed = true
        DispatchQueue.main.async { [weak self] in
            // An old event must not act on a new registration, even for the same chord.
            guard let self, self.registrations[shortcut]?.id == id else { return }
            self.lastTriggerUptime = uptime
            self.deliverHoldEvent(.interrupt, uptime: uptime)
            switch shortcut {
            case .toggle: self.toggle?()
            case .pasteLast: self.pasteLast?()
            case .command: self.command?()
            case .cancel: self.cancel?()
            }
        }
        return noErr
    }

    private func register(_ shortcut: Shortcut, key: UInt32, modifiers: UInt32) {
        guard registrations[shortcut] == nil else { return }
        var reference: EventHotKeyRef?
        Self.nextRegistrationID &+= 1
        let identity = EventHotKeyID(signature: Self.signature, id: Self.nextRegistrationID)
        let status = RegisterEventHotKey(key, modifiers, identity, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { registrations[shortcut] = Registration(reference: reference, id: identity.id) }
    }

    private func unregister(_ shortcut: Shortcut) {
        if let registration = registrations.removeValue(forKey: shortcut) { UnregisterEventHotKey(registration.reference) }
    }

    private var holdTapReady: Bool {
        guard let tap, let source else { return false }
        return CFMachPortIsValid(tap) && CFRunLoopSourceIsValid(source) && CGEvent.tapIsEnabled(tap: tap)
    }

    private func refreshHold() {
        guard !suspended, holdEnabled, CGPreflightListenEventAccess() else {
            removeHoldTap(notifyInterruption: !suspended)
            return
        }
        if holdTapReady { return }
        if let tap, let source, CFMachPortIsValid(tap), CFRunLoopSourceIsValid(source) {
            resetHold(notifyInterruption: true)
            CGEvent.tapEnable(tap: tap, enable: true)
            if holdTapReady { return }
        }
        removeHoldTap(notifyInterruption: true)
        installHoldTap()
    }

    private func installHoldTap() {
        let mask = CGEventMask((1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, kind, event, context in
            if let context {
                let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
                owner.handleHoldEvent(kind, event: event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return
        }
        tap = port
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func handleHoldEvent(_ kind: CGEventType, event: CGEvent) {
        guard !suspended, holdEnabled else { return }
        if kind == .tapDisabledByTimeout || kind == .tapDisabledByUserInput {
            holdGeneration &+= 1
            _ = gesture.reset()
            let generation = holdGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.suspended, self.holdGeneration == generation else { return }
                self.resetHold(notifyInterruption: true)
                self.refreshHold()
            }
            return
        }
        let flags = event.flags
        let solo = isSoloHold(flags: flags)
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(holdKey.code) else {
            if gesture.pressed, kind == .keyDown || (kind == .flagsChanged && !solo) {
                enqueueHoldEvent(.interrupt, event: event)
            }
            return
        }
        let down: Bool
        if holdKey.isModifier {
            guard kind == .flagsChanged else { return }
            down = modifierDown(flags: flags)
        } else {
            guard kind == .keyDown || kind == .keyUp else { return }
            // A repeat after wake or tap recovery is not a new press.
            if kind == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            down = kind == .keyDown
        }
        guard let transition = gesture.change(to: down) else { return }
        if transition {
            if solo { enqueueHoldEvent(.press, event: event) }
        } else {
            enqueueHoldEvent(.release, event: event)
        }
    }

    private func modifierDown(flags: CGEventFlags) -> Bool {
        if holdKey == .globe { return flags.contains(.maskSecondaryFn) }
        let sides = modifierSides
        let raw = flags.rawValue
        if raw & (sides.left | sides.right) != 0 { return raw & sides.right != 0 }
        // Virtual keyboards can omit side bits. Use live state only in that case.
        return flags.contains(sides.mask) && CGEventSource.keyState(.combinedSessionState, key: holdKey.code)
    }

    private var modifierSides: (mask: CGEventFlags, left: UInt64, right: UInt64) {
        switch holdKey {
        case .rightOption: return (.maskAlternate, UInt64(NX_DEVICELALTKEYMASK), UInt64(NX_DEVICERALTKEYMASK))
        case .rightControl: return (.maskControl, UInt64(NX_DEVICELCTLKEYMASK), UInt64(NX_DEVICERCTLKEYMASK))
        case .rightShift: return (.maskShift, UInt64(NX_DEVICELSHIFTKEYMASK), UInt64(NX_DEVICERSHIFTKEYMASK))
        case .globe, .f6: return (.maskSecondaryFn, 0, 0)
        }
    }

    private func isSoloHold(flags: CGEventFlags) -> Bool {
        let sides = modifierSides
        return flags.intersection(Self.modifiers).subtracting(sides.mask).isEmpty && flags.rawValue & sides.left == 0
    }

    private func enqueueHoldEvent(_ kind: HoldEvent, event: CGEvent) {
        let generation = holdGeneration
        let uptime = Double(event.timestamp) / 1_000_000_000
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.suspended, self.holdGeneration == generation else { return }
            self.deliverHoldEvent(kind, uptime: uptime)
        }
    }

    private func deliverHoldEvent(_ kind: HoldEvent, uptime: Double) {
        switch kind {
        case .press:
            // Wait briefly so a modifier used as part of a chord cannot start dictation.
            let candidate = UUID()
            pendingHold = candidate
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay) { [weak self] in
                guard let self, self.pendingHold == candidate, self.gesture.pressed else { return }
                self.pendingHold = nil
                self.deliveredHoldDown = true
                self.lastTriggerUptime = uptime
                self.hold?(true)
            }
        case .release, .interrupt:
            pendingHold = nil
            guard deliveredHoldDown else { return }
            deliveredHoldDown = false
            lastTriggerUptime = uptime
            if kind == .release { hold?(false) }
            else { holdInterrupted?() }
        }
    }

    private func resetHold(notifyInterruption: Bool) {
        holdGeneration &+= 1
        _ = gesture.reset()
        pendingHold = nil
        let interrupted = deliveredHoldDown
        deliveredHoldDown = false
        if interrupted && notifyInterruption { holdInterrupted?() }
    }

    private func removeHoldTap(notifyInterruption: Bool) {
        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        resetHold(notifyInterruption: notifyInterruption)
    }

    deinit {
        for shortcut in Shortcut.allCases { unregister(shortcut) }
        if let handler { RemoveEventHandler(handler) }
        removeHoldTap(notifyInterruption: false)
    }
}
