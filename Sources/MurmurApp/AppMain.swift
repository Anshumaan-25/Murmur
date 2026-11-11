import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import MurmurCore

@MainActor final class KeydownDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller: DictationController
    var item: NSStatusItem!
    var hub: Hub?
    var diagnosticObserver: NSObjectProtocol?
    private var backgroundLifecycle: BackgroundLifecycle?
    private var openedByLaunchServices = false
    private var launchedAtLogin = false
    private let speechReviewNotice = NSMenuItem(title: "Speech uncertain · use Copy Previous Text", action: nil, keyEquivalent: "")

    init(controller: DictationController? = nil) {
        self.controller = controller ?? DictationController()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        backgroundLifecycle = BackgroundLifecycle { [weak self] suspended in
            self?.controller.setSuspended(suspended)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
            || event?.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsServiceItem)) != nil
        openedByLaunchServices = !launchedAtLogin
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppMenus.install(settingsTarget: self, settingsAction: #selector(showSettings))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Keydown")
        let menu = NSMenu()
        menu.delegate = self
        speechReviewNotice.isHidden = true
        menu.addItem(speechReviewNotice)
        for (title, action, key) in [("Start / stop dictation", #selector(dictate), ""), ("Edit selected text", #selector(edit), ""), ("Paste previous text", #selector(previous), ""), ("Copy Previous Text", #selector(copyPrevious), ""), ("Review Previous Text", #selector(reviewPrevious), ""), ("Practice Dictation", #selector(practice), ""), ("Review Suggested Edit", #selector(reviewSuggestion), ""), ("Open Keydown", #selector(showHub), ""), ("Settings…", #selector(showSettings), ""), ("Quit Keydown", #selector(quit), "")] {
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
        if shouldShowWorkspace(arguments: CommandLine.arguments,
                               hasLaunched: UserDefaults.standard.bool(forKey: "hasLaunched")) {
            showHub()
        }
    }

    func shouldShowWorkspace(arguments: [String], hasLaunched: Bool) -> Bool {
        arguments.contains("--show")
            || (!arguments.contains("--background") && !launchedAtLogin && (openedByLaunchServices || !hasLaunched))
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.hotkeys.refresh()
        hub?.refreshPermissions()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if controller.preparingToQuit { return .terminateLater }
        guard !controller.hasLocalDialog else { return .terminateCancel }
        controller.beginQuit()
        Task { @MainActor [weak self] in
            guard let self else { sender.reply(toApplicationShouldTerminate: false); return }
            if let hub {
                hub.resolveDrafts { [weak self] allowed in self?.finishQuit(sender, allowed: allowed) }
            } else {
                finishQuit(sender, allowed: true)
            }
        }
        return .terminateLater
    }

    private func finishQuit(_ app: NSApplication, allowed: Bool) {
        guard allowed else {
            controller.cancelQuit()
            app.reply(toApplicationShouldTerminate: false)
            return
        }
        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(3)
            while LocalProcess.hasPendingWork || controller.validationTask != nil {
                guard ContinuousClock.now < deadline else {
                    controller.cancelQuit()
                    controller.announce("Keydown is still stopping local work. Try quitting again.")
                    app.reply(toApplicationShouldTerminate: false)
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            app.reply(toApplicationShouldTerminate: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.setSuspended(true)
        if let diagnosticObserver { DistributedNotificationCenter.default().removeObserver(diagnosticObserver) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !controller.isSuspended, !controller.preparingToQuit, !controller.hasLocalDialog else { return false }
        if controller.presentation.reopen(hasVisibleWindows: flag) { return flag }
        showHub()
        return false
    }
    func menuWillOpen(_ menu: NSMenu) {
        controller.hotkeys.refresh()
        speechReviewNotice.isHidden = !controller.lastDictationNeedsSpeechReview
        if let action = menu.items.first(where: { $0.action == #selector(dictate) }) {
            action.title = [.starting, .listening].contains(controller.sessions.phase) ? "Stop Dictation" : "Start Dictation"
        }
    }
    @objc func showHub() {
        guard !controller.isSuspended, !controller.preparingToQuit, !controller.hasLocalDialog else { return }
        if hub == nil { hub = Hub(controller: controller) }
        hub?.show()
        UserDefaults.standard.set(true, forKey: "hasLaunched")
    }
    @objc func showSettings() {
        showHub()
        guard let hub else { return }
        hub.navigation.selectedSegment = 4
        hub.navigate()
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
        guard arguments.allSatisfy({ $0 == "--show" || $0 == "--background" || $0.hasPrefix("-psn_") }),
              !(arguments.contains("--show") && arguments.contains("--background")) else { exit(64) }
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
