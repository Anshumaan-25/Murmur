import AppKit
import WebKit

final class FixtureApplication: NSApplication {
    weak var staleEditor: NSTextView?
    override var accessibilityFocusedUIElement: Any? {
        if CommandLine.arguments.contains("--opaque") { return nil }
        return staleEditor ?? super.accessibilityFocusedUIElement
    }
}
final class FixtureWindow: NSWindow {
    override var accessibilityFocusedUIElement: Any? { CommandLine.arguments.contains("--opaque") ? nil : super.accessibilityFocusedUIElement }
}

// An isolated, disposable destination for cross-process delivery checks.
final class FixtureDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let window = FixtureWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
    private let secondField = NSTextView(frame: NSRect(x: 12, y: 12, width: 616, height: 90))
    var otherWindow: NSWindow?
    var web: WKWebView?
    var checkedUndo = false
    func report(_ value: String, ready: Bool = true, formattingPreserved: Bool? = nil, receivedPaste: Bool? = nil) {
        var json: [String:Any] = ["ready":ready, "text":value, "other_text":secondField.string]
        if let formattingPreserved { json["formatting_preserved"] = formattingPreserved }
        if let receivedPaste { json["received_paste"] = receivedPaste }
        try? JSONSerialization.data(withJSONObject: json).write(to: output, options: .atomic)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Keydown insertion fixture"
        let menu = NSMenu(); let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let commands = NSMenu(title: "Edit")
        commands.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")); edit.submenu = commands; menu.addItem(edit); NSApp.mainMenu = menu
        if CommandLine.arguments.contains("--web") {
            let configuration = WKWebViewConfiguration(); configuration.userContentController.add(self, name: "fixture")
            let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 300), configuration: configuration); self.web = web; web.navigationDelegate = self; window.contentView = web
            let empty = CommandLine.arguments.contains("--empty")
            let selected = CommandLine.arguments.contains("--selected")
            let rich = CommandLine.arguments.contains("--rich")
            let pasteOnly = CommandLine.arguments.contains("--paste-only")
            let initial = empty ? "" : (selected ? "Prefix: REPLACE" : "Prefix: ")
            let field = rich
                ? "<div id='draft' role='textbox' aria-multiline='true' contenteditable='true'><strong>Prefix:</strong> draft.</div>"
                : "<textarea id='draft'>\(initial)</textarea>"
            web.loadHTMLString("""
                <html><body style="background:#181827;color:white;font:18px system-ui">
                <p>Disposable web text destination</p>\(field)
                <script>
                const field = document.getElementById('draft');
                let receivedPaste = false;
                const report = () => window.webkit.messageHandlers.fixture.postMessage({
                    text: field.value ?? field.textContent,
                    formatting: field.querySelector('strong')?.textContent === 'Prefix:',
                    receivedPaste
                });
                function focusDraft() {
                    field.focus();
                    if (field.isContentEditable) {
                        const range = document.createRange();
                        range.selectNodeContents(field);
                        range.collapse(false);
                        getSelection().removeAllRanges();
                        getSelection().addRange(range);
                    } else {
                        field.setSelectionRange(\(selected ? "8" : "field.value.length"), field.value.length);
                    }
                }
                field.addEventListener('paste', () => { receivedPaste = true; });
                if (\(pasteOnly)) {
                    field.addEventListener('beforeinput', event => {
                        if (event.inputType !== 'insertFromPaste') event.preventDefault();
                    });
                }
                field.addEventListener('input', report);
                window.onload = () => { focusDraft(); report(); };
                </script></body></html>
                """, baseURL: nil)
        } else {
            text.isRichText = false; text.isEditable = true; text.allowsUndo = true; text.delegate = self; text.font = .systemFont(ofSize: 20); text.setAccessibilityIdentifier("fixture-draft"); text.string = "Prefix: "; text.setSelectedRange(NSRange(location: 8, length: 0)); window.contentView = text; window.makeFirstResponder(text); if CommandLine.arguments.contains("--opaque") { text.setAccessibilityElement(false); window.setAccessibilityChildren([]) }; report(text.string)
            if CommandLine.arguments.contains("--disabled") { text.setAccessibilityEnabled(false) }
            if CommandLine.arguments.contains("--protected") { text.setAccessibilitySubrole(.secureTextField) }
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        if web == nil { window.makeFirstResponder(text) }
        if let index = CommandLine.arguments.firstIndex(of: "--switch-focus"), index + 1 < CommandLine.arguments.count {
            let trigger = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let container = NSView(frame: window.contentLayoutRect)
            window.contentView = container
            text.frame = NSRect(x: 12, y: 120, width: 616, height: 150)
            container.addSubview(text)
            secondField.string = "Unchanged second field"
            secondField.isEditable = true
            secondField.delegate = self
            container.addSubview(secondField)
            window.makeFirstResponder(text)
            report(text.string)
            Task { @MainActor in
                while !FileManager.default.fileExists(atPath: trigger.path) {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                guard window.makeFirstResponder(secondField) else { return }
                try? Data().write(to: trigger.appendingPathExtension("done"), options: .atomic)
            }
        }
        if CommandLine.arguments.contains("--stale-window") {
            let other = NSWindow(contentRect: NSRect(x: 320, y: 320, width: 240, height: 120),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            let stale = NSTextView(frame: other.contentLayoutRect)
            stale.string = "Synthetic editor in a different window"
            other.contentView = stale
            other.orderBack(nil)
            otherWindow = other
            (NSApp as? FixtureApplication)?.staleEditor = stale
        }
    }
    func textDidChange(_ notification: Notification) {
        report(text.string)
        if !checkedUndo, text.string.contains("Keydown insertion check") {
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
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let payload = message.body as? [String: Any], let text = payload["text"] as? String {
            report(text, formattingPreserved: payload["formatting"] as? Bool, receivedPaste: payload["receivedPaste"] as? Bool)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeFirstResponder(webView)
        webView.evaluateJavaScript("focusDraft()")
    }
}
let app = FixtureApplication.shared; let delegate = FixtureDelegate(); app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
