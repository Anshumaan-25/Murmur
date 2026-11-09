import AppKit
import AVFoundation
import ApplicationServices
import MurmurCore

@MainActor final class KeydownDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = DictationController()
    var item: NSStatusItem!
    var hub: Hub?
    var diagnosticObserver: NSObjectProtocol?
    private var backgroundLifecycle: BackgroundLifecycle?

    func applicationWillFinishLaunching(_ notification: Notification) {
        backgroundLifecycle = BackgroundLifecycle { [weak self] suspended in
            self?.controller.setSuspended(suspended)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Keydown")
        let menu = NSMenu()
        menu.delegate = self
        for (title, action, key) in [("Start / stop dictation", #selector(dictate), ""), ("Edit selected text", #selector(edit), ""), ("Paste previous text", #selector(previous), ""), ("Copy Previous Text", #selector(copyPrevious), ""), ("Review Previous Text", #selector(reviewPrevious), ""), ("Practice Dictation", #selector(practice), ""), ("Review Suggested Edit", #selector(reviewSuggestion), ""), ("Open Keydown", #selector(showHub), ","), ("Quit Keydown", #selector(quit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        controller.phaseChanged = { [weak self] phase in
            let symbol = phase == .listening ? "mic.fill" : (phase == .starting ? "mic" : (phase == .processing ? "ellipsis.circle" : "waveform"))
            self?.item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Keydown " + phase.rawValue)
            self?.item.button?.title = phase == .listening ? " REC" : ""
            self?.item.button?.toolTip = "Keydown · " + phase.rawValue
        }
        diagnosticObserver = DistributedNotificationCenter.default().addObserver(forName: LiveDiagnostics.request, object: nil, queue: .main) { [weak self] note in
            let inspect = note.userInfo?["inspect_focus"] as? Bool == true
            Task { @MainActor in
                guard let self else { return }
                if inspect { await LiveDiagnostics.inspectAndPublish(controller: self.controller) }
                else { LiveDiagnostics.publish(controller: self.controller) }
            }
        }
        LiveDiagnostics.publish(controller: controller)
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show") { showHub() }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        controller.hotkeys.refresh()
        hub?.refreshPermissions()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        controller.setSuspended(true)
        if let diagnosticObserver { DistributedNotificationCenter.default().removeObserver(diagnosticObserver) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showHub(); return true }
    func menuWillOpen(_ menu: NSMenu) {
        controller.hotkeys.refresh()
        if let action = menu.items.first(where: { $0.action == #selector(dictate) }) {
            action.title = [.starting, .listening].contains(controller.sessions.phase) ? "Stop Dictation" : "Start Dictation"
        }
    }
    @objc func showHub() {
        guard !controller.isSuspended else { return }
        if hub == nil { hub = Hub(controller: controller) }
        hub?.show()
        UserDefaults.standard.set(true, forKey: "hasLaunched")
    }
    @objc func dictate() { controller.toggle() }
    @objc func edit() { controller.start(command: true) }
    @objc func previous() { controller.pasteLast() }
    @objc func reviewPrevious() { controller.reviewLast() }
    @objc func practice() { controller.showPractice() }
    @objc func copyPrevious() { controller.copyLast() }
    @objc func reviewSuggestion() { controller.reviewSuggestedEdit() }
    @objc func quit() { NSApp.terminate(nil) }
}
@main struct KeydownEntry {
    @MainActor static func main() {
        #if KEYDOWN_FIXTURE
        guard Bundle.main.bundleIdentifier == "local.murmur.fixture" else { exit(64) }
        FixtureEntry.run()
        #else
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.contains("--diagnostics") {
            let result = LiveDiagnostics.read(inspectFocus: arguments.contains("--check-delivery"))
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        guard arguments.allSatisfy({ $0 == "--show" || $0.hasPrefix("-psn_") }) else { exit(64) }
        guard (try? PrivateStorage.directory(Preferences.directory)) != nil else { return }
        let path = Preferences.directory.appendingPathComponent("instance.lock")
        let lock = open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { return }
        defer { close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { return }
        let app = NSApplication.shared
        let delegate = KeydownDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
        #endif
    }
}
