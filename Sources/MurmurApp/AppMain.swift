import AppKit
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let view = self?.hub?.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
                }
                NSApp.terminate(nil)
            }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { controller.hotkeys.enableHold(controller.preferences.holdEnabled) }
    @objc func showHub() { hub?.show() }
    @objc func dictate() { controller.toggle() }
    @objc func edit() { controller.start(command: true) }
    @objc func previous() { controller.pasteLast() }
    @objc func quit() { controller.cancel(); NSApp.terminate(nil) }
}
@main struct MurmurEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = MurmurDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
