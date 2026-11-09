#if KEYDOWN_FIXTURE
import AppKit
import ApplicationServices
import MurmurCore

@MainActor enum FixtureEntry {
    static let targetBundle = "local.murmur.paste-target"
    static let text = "Keydown insertion check 世界."

    static func run() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            let result: [String: Any]
            var report: URL?
            if arguments.first == "--native-checks" {
                let audio = arguments.firstIndex(of: "--audio").flatMap { index in
                    arguments.dropFirst(index + 1).first.map { URL(fileURLWithPath: $0) }
                }
                let preview = arguments.firstIndex(of: "--preview-dir").flatMap { index in
                    arguments.dropFirst(index + 1).first.map { URL(fileURLWithPath: $0, isDirectory: true) }
                }
                result = await NativeChecks.run(audioURL: audio, withCleanup: arguments.contains("--with-cleanup"), previewDirectory: preview)
            } else if arguments.count >= 3, arguments[0] == "--fixture-insert", let pid = pid_t(arguments[1]), pid > 0 {
                report = URL(fileURLWithPath: arguments[2])
                result = await insert(pid: pid, moveCursor: arguments.contains("--move-fixture-cursor"))
            } else {
                result = ["passed": false, "error": "Unknown fixture arguments"]
            }
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
                if let report { try? data.write(to: report, options: .atomic) }
            }
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                app.postEvent(event, atStart: false)
            }
        }
        app.run()
    }

    private static func insert(pid: pid_t, moveCursor: Bool) async -> [String: Any] {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return ["error": "Grant Accessibility to Keydown Fixture."] }
        let continuity = FocusContinuity(pid: pid, toggleKey: 49, holdKey: nil)
        defer { continuity.stop() }
        let original = Destination.capture()
        guard original.pid == pid, original.bundle == targetBundle else { return ["error": "The owned fixture is not focused."] }
        if moveCursor {
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: down)?.postToPid(pid)
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        let inserter = ClipboardInserter()
        do {
            let outcome = try await inserter.insert(text, destination: original, continuity: continuity)
            return ["outcome": outcome.rawValue, "target_app": original.bundle, "delivery": inserter.lastAttempt]
        } catch {
            return ["error": error.localizedDescription]
        }
    }
}
#endif
