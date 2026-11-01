import AppKit
import MurmurCore

@MainActor enum NativeChecks {
    static func run(audioURL: URL? = nil, withCleanup: Bool = false) async -> [String: Any] {
        var results: [String: Bool] = [:]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 220))
        window.contentView = text; text.isEditable = true; text.isRichText = false; text.allowsUndo = true
        window.makeFirstResponder(text)
        text.string = "Alpha and Ω"; text.setSelectedRange(NSRange(location: 0, length: 5))
        text.insertText("Beta", replacementRange: text.selectedRange())
        results["native_selected_replacement"] = text.string == "Beta and Ω"
        text.undoManager?.undo(); results["native_undo"] = text.string == "Alpha and Ω"
        text.undoManager?.redo(); results["native_redo"] = text.string == "Beta and Ω"
        let board = NSPasteboard(name: .init("local.murmur.delivery." + UUID().uuidString))
        let item = NSPasteboardItem(); let custom = NSPasteboard.PasteboardType("local.murmur.fixture")
        item.setString("Saved fixture", forType: .string); item.setData(Data([0, 1, 128, 255]), forType: custom); board.writeObjects([item])
        let delivery = ClipboardDelivery()
        do {
            text.setSelectedRange(NSRange(location: 0, length: (text.string as NSString).length))
            try await delivery.deliver("Hello, 世界 👋", board: board, delay: 0.02) {
                results["native_paste_accepted"] = text.readSelection(from: board, type: .string)
            }
            results["native_unicode_paste"] = text.string == "Hello, 世界 👋"
            results["restored_text"] = board.string(forType: .string) == "Saved fixture"
            results["restored_binary"] = board.pasteboardItems?.first?.data(forType: custom) == Data([0, 1, 128, 255])
            try await delivery.deliver("Transient", board: board, delay: 0.02) { board.clearContents(); board.setString("A newer copy", forType: .string) }
            results["new_owner_preserved"] = board.string(forType: .string) == "A newer copy"
            do { try await delivery.deliver("Failure fixture", board: board, delay: 0.02) { throw MurmurError.empty }; results["failure_recovery"] = false }
            catch { results["failure_recovery"] = board.string(forType: .string) == "A newer copy" }
        } catch { results["clipboard_delivery"] = false }
        var pipelineTimes: [Double] = []; var modelUses = 0
        if let audioURL {
            do {
                let resources = Bundle.main.resourceURL!
                let provider = ExecutableSpeechProvider(executable: resources.appendingPathComponent("speech-decode"), model: resources.appendingPathComponent("speech-model.bin"))
                let frames = try AudioTools.readFile(audioURL)
                if withCleanup, CleanupQualification.load()?.eligible != true { throw MurmurError.unavailable("Qualify local cleanup before measuring it.") }
                for _ in 0..<3 {
                    let began = ProcessInfo.processInfo.systemUptime
                    let raw = try await provider.transcribe(AudioTools.trimmed(frames), language: "en-US", vocabulary: [])
                    let prepared: String
                    if withCleanup { let attempt = await SystemCleanup().attempt(raw.text, context: TextContext()); prepared = attempt.text; if attempt.usedModel { modelUses += 1 } }
                    else { prepared = RuleCleanup().apply(raw.text) }
                    text.setSelectedRange(NSRange(location: 0, length: (text.string as NSString).length))
                    try await delivery.deliver(prepared, board: board, delay: 0.35) { _ = text.readSelection(from: board, type: .string) }
                    results["fixture_pipeline"] = !prepared.isEmpty && text.string == prepared
                    pipelineTimes.append((ProcessInfo.processInfo.systemUptime - began) * 1000)
                }
            } catch { results["fixture_pipeline"] = false }
        }
        board.releaseGlobally()
        let indicator = Indicator()
        let previouslyFocused = NSApp.keyWindow
        let before = ProcessInfo.processInfo.systemUptime
        indicator.show("Checking indicator", phase: .listening); indicator.panel.displayIfNeeded()
        results["panel_nonactivating"] = !indicator.panel.canBecomeKey && !indicator.panel.canBecomeMain && NSApp.keyWindow === previouslyFocused
        results["panel_spaces"] = indicator.panel.collectionBehavior.contains(.canJoinAllSpaces) && indicator.panel.collectionBehavior.contains(.fullScreenAuxiliary)
        let elapsed = (ProcessInfo.processInfo.systemUptime - before) * 1000
        indicator.panel.orderOut(nil); window.orderOut(nil)
        let links = ["Privacy_Microphone", "Privacy_Accessibility", "Privacy_ListenEvent"]
        for link in links {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + link) { results["settings_handler_" + link] = NSWorkspace.shared.urlForApplication(toOpen: url) != nil }
        }
        return ["passed":results.values.allSatisfy { $0 }, "checks":results, "indicator_paint_dispatch_ms":elapsed, "fixture_pipeline_ms":pipelineTimes, "fixture_cleanup":withCleanup, "fixture_model_uses":modelUses, "scope":"App-owned text controls and named clipboard. No microphone or cross-application grant is exercised."]
    }
}
