import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import MurmurCore

@MainActor final class MurmurDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    var transcript = NSTextView()
    var item: NSStatusItem!
    var window: NSWindow?
    var status = NSTextField(labelWithString: "")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.status = { [weak self] text in self?.status.stringValue = text }
        controller.received = { [weak self] text in self?.transcript.string = text }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
        let menu = NSMenu()
        menu.addItem(withTitle: "Start / stop dictation", action: #selector(dictate), keyEquivalent: "")
        menu.addItem(withTitle: "Open Murmur", action: #selector(showHub), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Murmur", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }; item.menu = menu
        showHub()
    }
    @objc func showHub() {
        if window == nil {
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            created.title = "Murmur"; created.isReleasedWhenClosed = false
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
            stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
            let title = NSTextField(labelWithString: "Murmur"); title.font = .systemFont(ofSize: 32, weight: .bold); stack.addArrangedSubview(title)
            stack.addArrangedSubview(NSTextField(labelWithString: "Your voice, kept on your Mac."))
            for (label, action) in [("Enable microphone", #selector(microphone)), ("Accessibility settings", #selector(accessibility)), ("Input Monitoring settings (optional)", #selector(monitoring)), ("Toggle launch at login", #selector(startup)), ("Refresh permission status", #selector(refresh))] {
                stack.addArrangedSubview(NSButton(title: label, target: self, action: action))
            }
            stack.addArrangedSubview(NSButton(title: "Start / stop · Control Option Space", target: self, action: #selector(dictate)))
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = transcript; scroll.heightAnchor.constraint(equalToConstant: 140).isActive = true; scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 650).isActive = true; transcript.isEditable = false; stack.addArrangedSubview(scroll)
            status.maximumNumberOfLines = 5; status.lineBreakMode = .byWordWrapping; stack.addArrangedSubview(status)
            created.contentView = stack; created.center(); window = created
        }
        refresh(); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc func dictate() { controller.toggle() }
    @objc func microphone() { AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refresh() } } }
    @objc func accessibility() { openPrivacy("Privacy_Accessibility") }
    @objc func monitoring() { openPrivacy("Privacy_ListenEvent") }
    @objc func startup() { do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { status.stringValue = error.localizedDescription } }
    @objc func refresh() { status.stringValue = "Microphone: \(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "ready" : "not granted")\nInsertion: \(AXIsProcessTrusted() ? "ready" : "grant Accessibility")\nHold shortcut: \(CGPreflightListenEventAccess() ? "ready" : "grant Input Monitoring")" }
    func openPrivacy(_ anchor: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) { NSWorkspace.shared.open(url) } }
    @objc func quit() { NSApp.terminate(nil) }
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
