import AppKit
import Carbon

final class Hotkeys {
    var toggle: (() -> Void)?
    var cancel: (() -> Void)?
    var pasteLast: (() -> Void)?
    var command: (() -> Void)?
    var hold: ((Bool) -> Void)?
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            var identity = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            DispatchQueue.main.async {
                switch identity.id { case 1: owner.toggle?(); case 2: owner.pasteLast?(); case 3: owner.command?(); case 4: owner.cancel?(); default: break }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        configure(keyCode: 49)
        register(2, key: 9, modifiers: UInt32(controlKey | optionKey))
        register(3, key: 15, modifiers: UInt32(controlKey | optionKey))
    }
    func configure(keyCode: UInt32) { unregister(1); register(1, key: keyCode, modifiers: UInt32(controlKey | optionKey)) }
    private func register(_ id: UInt32, key: UInt32, modifiers: UInt32) {
        var reference: EventHotKeyRef?
        if RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4D55524D, id: id), GetApplicationEventTarget(), 0, &reference) == noErr, let reference { references[id] = reference }
    }
    private func unregister(_ id: UInt32) { if let ref = references.removeValue(forKey: id) { UnregisterEventHotKey(ref) } }
    func escape(_ active: Bool) { if active { if references[4] == nil { register(4, key: 53, modifiers: 0) } } else { unregister(4) } }
    func enableHold(_ enabled: Bool) {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; held = false
        guard enabled, CGPreflightListenEventAccess() else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, kind, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            if kind == .tapDisabledByTimeout || kind == .tapDisabledByUserInput { if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }; return Unmanaged.passUnretained(event) }
            if event.getIntegerValueField(.keyboardEventKeycode) == 63 {
                let down = event.flags.contains(.maskSecondaryFn)
                if down != owner.held { owner.held = down; DispatchQueue.main.async { owner.hold?(down) } }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = port; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: port, enable: true)
    }
    deinit { for ref in references.values { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) }; if let tap { CGEvent.tapEnable(tap: tap, enable: false) }; if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) } }
}
