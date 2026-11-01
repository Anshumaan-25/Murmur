import AppKit
import ApplicationServices
import MurmurCore

/// A recording-scoped proof that an opaque editor's keyboard focus has not been moved by the user.
/// AX still verifies the app/window and protected input; this fills the gap when no field is exposed.
final class FocusContinuity {
    let pid: pid_t
    private let toggleKey: UInt16
    private let holdKey: UInt16?
    private var activity = FocusActivity()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observer: NSObjectProtocol?
    private(set) var available = false
    var unchanged: Bool {
        guard available, let tap, CGEvent.tapIsEnabled(tap: tap) else { return false }
        return activity.unchanged
    }
    init(pid: pid_t, toggleKey: UInt16, holdKey: UInt16?) {
        self.pid = pid; self.toggleKey = toggleKey; self.holdKey = holdKey
        guard pid > 0, AXIsProcessTrusted(), CGPreflightListenEventAccess() else { return }
        let kinds: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        let mask = kinds.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, kind, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<FocusContinuity>.fromOpaque(context).takeUnretainedValue()
            if kind == .keyDown {
                let flags = event.flags
                let chord = flags.contains([.maskControl, .maskAlternate]) && flags.intersection([.maskCommand, .maskShift]).isEmpty
                owner.activity.key(UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), dictationChord: chord, toggleKey: owner.toggleKey, holdKey: owner.holdKey)
            } else { owner.activity.invalidate() }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
        self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true); available = true
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.processIdentifier != self.pid { self.activity.invalidate() }
        }
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
