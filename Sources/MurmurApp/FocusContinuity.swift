import AppKit
import ApplicationServices
import MurmurCore

/// Records evidence of intervening focus changes during a delivery attempt.
final class FocusContinuity {
    let pid: pid_t
    private let toggleKey: UInt16
    private let holdKey: UInt16?
    private var activity = FocusActivity()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?
    private(set) var available = false
    var invalidated: Bool {
        !activity.unchanged || (available && tap.map { !CGEvent.tapIsEnabled(tap: $0) } != false)
    }
    init(pid: pid_t, toggleKey: UInt16, holdKey: UInt16?) {
        self.pid = pid; self.toggleKey = toggleKey; self.holdKey = holdKey
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.processIdentifier != self.pid { self.activity.invalidate() }
        }
        guard pid > 0, AXIsProcessTrusted(), CGPreflightListenEventAccess() else { return }
        let kinds: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        let mask = kinds.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, kind, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<FocusContinuity>.fromOpaque(context).takeUnretainedValue()
            if kind == .keyDown {
                let flags = event.flags
                let chord = flags.contains([.maskControl, .maskAlternate]) && flags.intersection([.maskCommand, .maskShift]).isEmpty
                let standalone = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskHelp]).isEmpty
                owner.activity.key(UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), dictationChord: chord, toggleKey: owner.toggleKey, holdKey: owner.holdKey, standaloneHold: standalone)
            } else { owner.activity.invalidate() }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { self.tap = nil; return }
        self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true); available = true

    }
    func stop() {
        available = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        source = nil; tap = nil; observer = nil
    }
    deinit { stop() }
}
