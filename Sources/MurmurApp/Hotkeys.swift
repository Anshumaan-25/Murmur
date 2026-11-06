import AppKit
import Carbon
import MurmurCore

final class Hotkeys {
    private enum Shortcut: UInt32, CaseIterable {
        case toggle = 1, pasteLast, command, cancel
    }

    var toggle: (() -> Void)?
    var cancel: (() -> Void)?
    var pasteLast: (() -> Void)?
    var command: (() -> Void)?
    var hold: ((Bool) -> Void)?
    var holdInterrupted: (() -> Void)?

    private static let signature: OSType = 0x4D55524D
    private var references: [Shortcut: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var toggleKeyCode: UInt32 = 49
    private var escapeRequested = false
    private var suspended = false
    private var shortcutGeneration: UInt64 = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = HoldGesture()
    private var holdKey = HoldKey.globe
    private var holdEnabled = false
    private var holdGeneration: UInt64 = 0
    private var deliveredHoldDown = false
    private(set) var lastTriggerUptime = ProcessInfo.processInfo.systemUptime

    var availabilityMessage: String? {
        if suspended { return "Shortcuts are paused while this Mac session is inactive." }
        if references[.toggle] == nil {
            return "Could not register the dictation shortcut. Choose another shortcut in Settings or start from the menu bar."
        }
        if references[.pasteLast] == nil || references[.command] == nil {
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
            shortcutGeneration &+= 1
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
        shortcutGeneration &+= 1
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
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == Hotkeys.signature,
                  let shortcut = Shortcut(rawValue: identity.id),
                  !owner.suspended, owner.references[shortcut] != nil else { return OSStatus(eventNotHandledErr) }
            let generation = owner.shortcutGeneration
            let uptime = GetEventTime(event)
            DispatchQueue.main.async { [weak owner] in
                guard let owner, !owner.suspended, owner.shortcutGeneration == generation,
                      owner.references[shortcut] != nil else { return }
                owner.lastTriggerUptime = uptime
                switch shortcut {
                case .toggle: owner.toggle?()
                case .pasteLast: owner.pasteLast?()
                case .command: owner.command?()
                case .cancel: owner.cancel?()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { handler = nil }
    }

    private func register(_ shortcut: Shortcut, key: UInt32, modifiers: UInt32) {
        guard references[shortcut] == nil else { return }
        var reference: EventHotKeyRef?
        let identity = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
        let status = RegisterEventHotKey(key, modifiers, identity, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { references[shortcut] = reference }
    }

    private func unregister(_ shortcut: Shortcut) {
        if let reference = references.removeValue(forKey: shortcut) { UnregisterEventHotKey(reference) }
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

    private func handleHoldEvent(_ kind: CGEventType, event: CGEvent) {
        guard !suspended else { return }
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
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(holdKey.code) else { return }
        let down: Bool
        if holdKey.isModifier {
            guard kind == .flagsChanged else { return }
            down = CGEventSource.keyState(.combinedSessionState, key: holdKey.code)
        } else {
            guard kind == .keyDown || kind == .keyUp else { return }
            // A repeat after wake or tap recovery is not a new press.
            if kind == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            down = kind == .keyDown
        }
        guard let transition = gesture.change(to: down) else { return }
        let generation = holdGeneration
        let uptime = Double(event.timestamp) / 1_000_000_000
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.suspended, self.holdGeneration == generation else { return }
            self.lastTriggerUptime = uptime
            self.deliveredHoldDown = transition
            self.hold?(transition)
        }
    }

    private func resetHold(notifyInterruption: Bool) {
        holdGeneration &+= 1
        _ = gesture.reset()
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
