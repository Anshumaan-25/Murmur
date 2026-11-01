import AppKit
import WebKit

final class FixtureApplication: NSApplication {
    override var accessibilityFocusedUIElement: Any? { CommandLine.arguments.contains("--opaque") ? nil : super.accessibilityFocusedUIElement }
}
final class FixtureWindow: NSWindow {
    override var accessibilityFocusedUIElement: Any? { CommandLine.arguments.contains("--opaque") ? nil : super.accessibilityFocusedUIElement }
}

// An isolated, disposable destination for cross-process delivery checks.
final class FixtureDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let window = FixtureWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
    var web: WKWebView?
    var checkedUndo = false
    func report(_ value: String, ready: Bool = true) {
        let json: [String:Any] = ["ready":ready, "text":value]
        try? JSONSerialization.data(withJSONObject: json).write(to: output, options: .atomic)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Murmur insertion fixture"
        let menu = NSMenu(); let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let commands = NSMenu(title: "Edit")
        commands.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")); edit.submenu = commands; menu.addItem(edit); NSApp.mainMenu = menu
        if CommandLine.arguments.contains("--web") {
            let configuration = WKWebViewConfiguration(); configuration.userContentController.add(self, name: "fixture")
            let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 300), configuration: configuration); self.web = web; web.navigationDelegate = self; window.contentView = web
            web.loadHTMLString("<html><body style='background:#181827;color:white;font:18px system-ui'><p>Disposable web text destination</p><textarea id='draft' aria-label='Fixture draft' style='width:90%;height:120px' oninput='window.webkit.messageHandlers.fixture.postMessage(this.value)'>Prefix: </textarea><script>window.onload=()=>{let e=document.getElementById('draft');e.focus();e.setSelectionRange(e.value.length,e.value.length);window.webkit.messageHandlers.fixture.postMessage(e.value)}</script></body></html>", baseURL: nil)
        } else {
            text.isRichText = false; text.isEditable = true; text.allowsUndo = true; text.delegate = self; text.font = .systemFont(ofSize: 20); text.setAccessibilityIdentifier("fixture-draft"); text.string = "Prefix: "; text.setSelectedRange(NSRange(location: 8, length: 0)); window.contentView = text; window.makeFirstResponder(text); if CommandLine.arguments.contains("--opaque") { text.setAccessibilityElement(false); window.setAccessibilityChildren([]) }; report(text.string)
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        if web == nil { window.makeFirstResponder(text) }
    }
    func textDidChange(_ notification: Notification) {
        report(text.string)
        if !checkedUndo, text.string.contains("Murmur insertion check") {
            checkedUndo = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                let delivered = text.string
                text.undoManager?.undo(); let undone = text.string == "Prefix: "
                text.undoManager?.redo(); let redone = text.string == delivered
                let json: [String:Any] = ["ready":true, "text":text.string, "undo_restored":undone, "redo_restored":redone]
                try? JSONSerialization.data(withJSONObject: json).write(to: output, options: .atomic)
            }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { if let value = message.body as? String { report(value) } }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeFirstResponder(webView)
        webView.evaluateJavaScript("let e=document.getElementById('draft');e.focus();e.setSelectionRange(e.value.length,e.value.length)")
    }
}
let app = FixtureApplication.shared; let delegate = FixtureDelegate(); app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
