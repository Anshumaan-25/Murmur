import AppKit
import AVFoundation
import ApplicationServices
import MurmurCore

@MainActor final class MurmurDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    var item: NSStatusItem!
    var hub: Hub?
    var diagnosticObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
        let menu = NSMenu()
        for (title, action, key) in [("Start / stop dictation", #selector(dictate), ""), ("Edit selected text", #selector(edit), ""), ("Paste previous text", #selector(previous), ""), ("Open Murmur", #selector(showHub), ","), ("Quit Murmur", #selector(quit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        hub = Hub(controller: controller, preview: CommandLine.arguments.contains("--snapshot"))
        diagnosticObserver = DistributedNotificationCenter.default().addObserver(forName: LiveDiagnostics.request, object: nil, queue: .main) { [weak self] note in
            let inspect = note.userInfo?["inspect_focus"] as? Bool == true
            Task { @MainActor in
                guard let self else { return }
                if inspect { await LiveDiagnostics.inspectAndPublish(controller: self.controller) }
                else { LiveDiagnostics.publish(controller: self.controller) }
            }
        }
        LiveDiagnostics.publish(controller: controller)
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--snapshot") { showHub(); UserDefaults.standard.set(true, forKey: "hasLaunched") }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            if let pageIndex = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.count > pageIndex + 1, let page = Int(CommandLine.arguments[pageIndex + 1]), (0...4).contains(page) {
                hub?.page = page; hub?.navigation.selectedSegment = page; hub?.render()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let view = self?.hub?.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    func invalidate(_ child: NSView) { child.needsDisplay = true; for descendant in child.subviews { invalidate(descendant) } }
                    invalidate(view); view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
                }
                NSApp.terminate(nil)
            }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { controller.hotkeys.enableHold(controller.preferences.holdEnabled, key: controller.preferences.holdKey); hub?.refreshPermissions() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showHub(); return true }
    @objc func showHub() { hub?.show() }
    @objc func dictate() { controller.toggle() }
    @objc func edit() { controller.start(command: true) }
    @objc func previous() { controller.pasteLast() }
    @objc func quit() { controller.cancel(); NSApp.terminate(nil) }
}
@main struct MurmurEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--native-checks") {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                let arguments = CommandLine.arguments
                var audio: URL?
                if let index = arguments.firstIndex(of: "--audio"), arguments.count > index + 1 { audio = URL(fileURLWithPath: arguments[index + 1]) }
                let result = await NativeChecks.run(audioURL: audio, withCleanup: arguments.contains("--with-cleanup"))
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
                app.stop(nil)
                app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
            }
            app.run(); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--indicator-snapshot"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let indicator = Indicator(); indicator.inputLevel = { 0.03 }; indicator.show("Listening…", phase: .listening)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let view = indicator.content
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); try? bitmap.representation(using: .png, properties: [:])?.write(to: output) }
                indicator.hide(); app.stop(nil)
                app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
            }
            app.run(); return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            let result = LiveDiagnostics.read(inspectFocus: CommandLine.arguments.contains("--check-delivery"))
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--test-insert"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            let text = CommandLine.arguments[index + 1]
            let reportURL: URL? = CommandLine.arguments.firstIndex(of: "--insert-report").flatMap { CommandLine.arguments.count > $0 + 1 ? URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) : nil }
            Task { @MainActor in
                let preferences = Preferences.load()
                let continuity = FocusContinuity(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, toggleKey: UInt16(clamping: preferences.toggleKey), holdKey: preferences.holdEnabled ? UInt16(preferences.holdKey.code) : nil)
                defer { continuity.stop() }
                let initial = Destination.capture()
                let destination = (try? await Destination.prepared(initial)) ?? initial; let inserter = ClipboardInserter()
                let savedClipboard = reportURL == nil ? nil : try? PasteboardSnapshot(NSPasteboard.general)
                var report: [String:Any] = ["accessibility":AXIsProcessTrusted(), "event_posting":CGPreflightPostEventAccess(), "initial_role":initial.role, "role":destination.role, "editable":destination.editable, "has_selection":destination.selection != nil, "target_app":destination.bundle]
                report["front_pid"] = destination.pid
                for (name, source) in [("app", AXUIElementCreateApplication(destination.pid)), ("system", AXUIElementCreateSystemWide())] {
                    var ref: CFTypeRef?; let status = AXUIElementCopyAttributeValue(source, kAXFocusedUIElementAttribute as CFString, &ref); report[name + "_focus_status"] = status.rawValue
                    if let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() { var owner: pid_t = 0; _ = AXUIElementGetPid(unsafeBitCast(ref, to: AXUIElement.self), &owner); report[name + "_focus_pid"] = owner }
                }
                do {
                    if let expected = CommandLine.arguments.firstIndex(of: "--expected-target"), CommandLine.arguments.count > expected + 1, destination.bundle != CommandLine.arguments[expected + 1] { throw MurmurError.unavailable("Insertion check skipped: the fixture is not the focused application.") }
                    if CommandLine.arguments.contains("--move-fixture-cursor") {
                        guard destination.bundle == "local.murmur.paste-target", NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid else { throw MurmurError.unavailable("Cursor check requires the focused fixture.") }
                        let source = CGEventSource(stateID: .privateState)
                        for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 124, keyDown: down); event?.flags = []; event?.post(tap: .cghidEventTap) }
                        try await Task.sleep(nanoseconds: 80_000_000)
                    }
                    if CommandLine.arguments.contains("--dry-run") {
                        let current = Destination.capture()
                        let reason = destination.reason(comparedTo: current, opaqueFocusStable: continuity.pid == destination.pid && continuity.unchanged)
                        report["reason"] = reason.rawValue; report["outcome"] = reason == .ready ? "ready" : "blocked"
                        report["delivery"] = ["original":destination.diagnostic, "current":current.diagnostic, "focus_tracking_available":continuity.available, "focus_unchanged":continuity.unchanged]
                    } else {
                        let result = try await inserter.insert(text, destination: destination, continuity: continuity); report["outcome"] = result.rawValue; report["reason"] = inserter.lastReason.rawValue; report["delivery"] = inserter.lastAttempt
                    }
                }
                catch { report["error"] = error.localizedDescription }
                if let copiedCount = inserter.copiedChangeCount { _ = savedClipboard?.restore(NSPasteboard.general, ifUnchangedSince: copiedCount) }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys) { print(String(decoding: data, as: UTF8.self)); if let reportURL { try? data.write(to: reportURL, options: .atomic) } }
                app.stop(nil)
                app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
            }
            app.run(); return
        }
        let delegate = MurmurDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
