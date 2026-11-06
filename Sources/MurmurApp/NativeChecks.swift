import AppKit
import Carbon
import MurmurCore

@MainActor enum NativeChecks {
    static func run(audioURL: URL? = nil, withCleanup: Bool = false) async -> [String: Any] {
        var results: [String: Bool] = [:]
        do {
            let shortcuts = Hotkeys()
            let testKey = UInt32(kVK_F20)
            shortcuts.configure(keyCode: testKey)
            results["shortcut_initial_registration"] = shortcuts.availabilityMessage == nil
            shortcuts.suspend()

            var blocker: EventHotKeyRef?
            let testIdentity = EventHotKeyID(signature: 0x4B44544B, id: 1)
            let reservation = RegisterEventHotKey(testKey, UInt32(controlKey | optionKey), testIdentity, GetApplicationEventTarget(), 0, &blocker)
            results["shortcut_suspend_releases_chord"] = reservation == noErr && blocker != nil
            if let blocker {
                shortcuts.resume()
                results["shortcut_registration_conflict_reported"] = shortcuts.availabilityMessage?.hasPrefix("Could not register the dictation shortcut.") == true
                UnregisterEventHotKey(blocker)
                shortcuts.refresh()
                results["shortcut_registration_recovers"] = shortcuts.availabilityMessage == nil
            }
        }
        do {
            let center = NotificationCenter()
            var changes: [Bool] = []
            let lifecycle = BackgroundLifecycle(center: center) { changes.append($0) }
            withExtendedLifetime(lifecycle) {
                center.post(name: NSWorkspace.willSleepNotification, object: nil)
                center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
                center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
                center.post(name: NSWorkspace.didWakeNotification, object: nil)
                center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
                results["background_waits_for_all_interruptions"] = changes == [true]
                center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
                results["background_resumes_once"] = changes == [true, false]
            }
        }
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

            let center = NotificationCenter()
            let lifecycle = BackgroundLifecycle(center: center) { suspended in
                if suspended { delivery.finish() }
            }
            try await delivery.deliver("Clipboard during interruption", board: board, delay: 0.05) {
                DispatchQueue.main.async {
                    center.post(name: NSWorkspace.willSleepNotification, object: nil)
                    results["background_restores_pending_clipboard"] = board.string(forType: .string) == "A newer copy"
                }
            }
            withExtendedLifetime(lifecycle) {}
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
        indicator.inputLevel = { 0.03 }
        try? await Task.sleep(nanoseconds: 350_000_000)
        results["panel_audio_response"] = indicator.content.amplitude > 0.1 && indicator.animating
        let frameMedian = SessionMeasurements.median(indicator.frameIntervals.map { $0 * 1000 }) ?? 0
        indicator.hide(); results["panel_timer_stops"] = !indicator.animating && !indicator.panel.isVisible; window.orderOut(nil)
        let links = ["Privacy_Microphone", "Privacy_Accessibility", "Privacy_ListenEvent"]
        for link in links {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + link) { results["settings_handler_" + link] = NSWorkspace.shared.urlForApplication(toOpen: url) != nil }
        }
        return ["passed":results.values.allSatisfy { $0 }, "checks":results, "indicator_paint_dispatch_ms":elapsed, "indicator_frame_median_ms":frameMedian, "fixture_pipeline_ms":pipelineTimes, "fixture_cleanup":withCleanup, "fixture_model_uses":modelUses, "scope":"App-owned text controls and named clipboard. No microphone or cross-application grant is exercised."]
    }
}
