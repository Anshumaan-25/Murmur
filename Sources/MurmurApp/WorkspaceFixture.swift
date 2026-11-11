#if KEYDOWN_FIXTURE
import AppKit
import MurmurCore

@MainActor final class WorkspaceFixture: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private let clipboard = ClipboardDelivery()
    private lazy var delegate = KeydownDelegate(controller: DictationController(ephemeral: true, clipboard: clipboard))
    private var board: NSPasteboard?
    private var report: URL?
    private var readyFile: URL?
    private var delayingQuit = false
    private var launchEvents: [String] = []

    init(arguments: [String]) { self.arguments = arguments }

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchEvents.append("willFinish")
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        launchEvents.append("untitled")
        return delegate.applicationShouldOpenUntitledFile(sender)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchEvents.append("reopen")
        if arguments.first == "--workspace-preview" { delegate.hub?.show() }
        writeLaunchReport()
        return false
    }

    private func writeLaunchReport() {
        guard arguments.first == "--launch-probe", arguments.count >= 2 else { return }
        let show = delegate.shouldShowWorkspace(arguments: arguments, hasLaunched: true)
        let data = try? JSONSerialization.data(withJSONObject: ["events": launchEvents, "should_show": show], options: [.sortedKeys])
        try? data?.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchEvents.append("didFinish")
        writeLaunchReport()
        switch arguments.first {
        case "--workspace-preview":
            if arguments.dropFirst().first == "accessory" {
                delegate.controller.presentation = AppPresentation(setPolicy: { _ in false })
            }
            let hub = Hub(controller: delegate.controller)
            delegate.hub = hub
            hub.window?.title = "Keydown Window Fixture"
            if arguments.dropFirst().first != "primary" { hub.window?.collectionBehavior = [] }
            AppMenus.install(settingsTarget: hub, settingsAction: #selector(Hub.navigate))
            hub.show()
        case "--quit-fixture":
            guard arguments.count == 4 else { exit(64) }
            let mode = arguments[1]
            let ready = URL(fileURLWithPath: arguments[2])
            readyFile = ready
            if mode == "dirty" {
                let hub = Hub(controller: delegate.controller)
                delegate.hub = hub
                hub.selectPage(1)
                hub.words.string = "Unsaved synthetic vocabulary"
            }
            report = ready.appendingPathExtension("result")
            let board = NSPasteboard(name: .init(arguments[3]))
            self.board = board
            board.clearContents()
            board.setString("original fixture clipboard", forType: .string)
            delegate.controller.activeTask = Task {
                _ = try? await LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "printf '%s' \"$$\" > \"$1\"; exec /bin/sleep 30", "fixture",
                                ready.appendingPathExtension("child").path],
                    input: Data(), timeout: 25)
            }
            Task {
                try? await clipboard.deliver("temporary fixture text", board: board, delay: 2) {
                    if mode == "new-owner" {
                        board.clearContents()
                        board.setString("new fixture owner", forType: .string)
                    }
                    try Data("ready".utf8).write(to: ready, options: .atomic)
                }
            }
        case "--launch-probe": break
        default: exit(64)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if arguments.first == "--quit-fixture", let mode = arguments.dropFirst().first, let readyFile {
            if mode == "refuse", !FileManager.default.fileExists(atPath: readyFile.appendingPathExtension("allow").path) {
                return .terminateCancel
            }
            if mode == "delayed" {
                guard !delayingQuit else { return .terminateLater }
                delayingQuit = true
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    _ = delegate.applicationShouldTerminate(sender)
                }
                return .terminateLater
            }
        }
        let reply = delegate.applicationShouldTerminate(sender)
        if arguments.dropFirst().first == "dirty", reply == .terminateLater, let readyFile {
            Task {
                guard let hub = delegate.hub, let window = hub.window else { return }
                let deadline = ContinuousClock.now + .seconds(2)
                while window.attachedSheet == nil, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(15))
                }
                guard let sheet = window.attachedSheet else { return }
                let allow = FileManager.default.fileExists(atPath: readyFile.appendingPathExtension("allow").path)
                let decision = allow ? "discard" : "cancel"
                try? Data(decision.utf8).write(to: readyFile.appendingPathExtension("decision"), options: .atomic)
                window.endSheet(sheet, returnCode: allow ? .alertSecondButtonReturn : .alertThirdButtonReturn)
            }
        }
        return reply
    }

    func applicationWillTerminate(_ notification: Notification) {
        delegate.applicationWillTerminate(notification)
        if let board, let report {
            let value = board.string(forType: .string) ?? ""
            try? Data(value.utf8).write(to: report, options: .atomic)
            board.releaseGlobally()
        }
    }
}
#endif
