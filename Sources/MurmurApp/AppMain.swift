import AppKit
import AVFoundation
import ApplicationServices
import MurmurCore

@MainActor final class MurmurDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    var item: NSStatusItem!
    var hub: Hub?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
        let menu = NSMenu()
        for (title, action, key) in [("Start / stop dictation", #selector(dictate), ""), ("Edit selected text", #selector(edit), ""), ("Paste previous text", #selector(previous), ""), ("Open Murmur", #selector(showHub), ","), ("Quit Murmur", #selector(quit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        hub = Hub(controller: controller)
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
    func applicationDidBecomeActive(_ notification: Notification) { controller.hotkeys.enableHold(controller.preferences.holdEnabled, key: controller.preferences.holdKey) }
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
        if CommandLine.arguments.contains("--diagnostics") {
            let resources = Bundle.main.resourceURL!
            let result: [String: Any] = ["microphone_authorized": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "accessibility_authorized": AXIsProcessTrusted(), "monitoring_authorized": CGPreflightListenEventAccess(), "speech_model_bundled": FileManager.default.fileExists(atPath: resources.appendingPathComponent("speech-model.bin").path), "editing_model_bundled": FileManager.default.fileExists(atPath: resources.appendingPathComponent("editing-model.gguf").path), "automatic_model_cleanup": Preferences.load().useModel && CleanupQualification.load()?.eligible == true, "local_cleanup_qualified": CleanupQualification.load()?.eligible == true]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--test-insert"), CommandLine.arguments.count > index + 1 {
            app.setActivationPolicy(.accessory)
            guard AXIsProcessTrusted() else { print("Accessibility grant is required for insertion verification."); return }
            let text = CommandLine.arguments[index + 1]
            Task { @MainActor in
                do { let result = try await ClipboardInserter().insert(text, destination: Destination.capture()); print("Insertion check: \(result.rawValue)") } catch { print(error.localizedDescription) }
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
