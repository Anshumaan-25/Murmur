#if KEYDOWN_FIXTURE
import AppKit
import Carbon
import IOKit.hidsystem
import MurmurCore

@MainActor enum NativeChecks {
    static func run(audioURL: URL? = nil, withCleanup: Bool = false, previewDirectory: URL? = nil) async -> [String: Any] {
        var results = await shortcutGestures()
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
                let provider = ExecutableSpeechProvider(executable: resources.appendingPathComponent("speech-decode"), model: resources.appendingPathComponent("speech-model.bin"), privateProtocol: FileManager.default.fileExists(atPath: resources.appendingPathComponent("speech-protocol.json").path))
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
        results["panel_final_window_level"] = indicator.panel.level == .statusBar
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
        let lifecycleCenter = NotificationCenter()
        let panelLifecycle = BackgroundLifecycle(center: lifecycleCenter) { suspended in if suspended { indicator.hide() } }
        indicator.show("Completed", phase: .idle)
        lifecycleCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        results["panel_suspension_hides"] = !indicator.panel.isVisible && !indicator.animating
        lifecycleCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        results["wake_does_not_imply_recording"] = !indicator.panel.isVisible
        indicator.panel.alphaValue = 0
        indicator.panel.level = .floating
        indicator.show("Listening after wake", phase: .listening)
        try? await Task.sleep(nanoseconds: 2_100_000_000)
        results["panel_recovers_after_wake"] = indicator.panel.isVisible && indicator.panel.alphaValue == 1 && indicator.panel.level == .statusBar
        results["old_dismissal_cannot_hide_new_capture"] = indicator.animating
        results["panel_frame_on_display"] = NSScreen.screens.contains { $0.visibleFrame.contains(indicator.panel.frame) }
        indicator.hide()
        withExtendedLifetime(panelLifecycle) {}
        let reviewBoard = NSPasteboard(name: .init("local.murmur.review." + UUID().uuidString))
        reviewBoard.setString("Original clipboard", forType: .string)
        let review = ResultReviewController(board: reviewBoard)
        review.update(raw: "recognized fixture", cleaned: "Formatted fixture.", outcome: "Available for copy")
        if let previewDirectory, let view = review.window?.contentView {
            review.update(raw: "Schedule our meeting at 5.15 p.m. Actually make that 5.50 p.m.", cleaned: "Schedule our meeting at 5:50 PM.", outcome: "Available for copy")
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    do {
                        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        try data.write(to: previewDirectory.appendingPathComponent("result-review.png"))
                        results["review_preview_rendered"] = true
                    } catch { results["review_preview_rendered"] = false }
                }
            }
            review.update(raw: "recognized fixture", cleaned: "Formatted fixture.", outcome: "Available for copy")
        }
        results["review_keeps_both_stages"] = review.rawText == "recognized fixture" && review.formattedText == "Formatted fixture."
        results["review_does_not_copy_automatically"] = reviewBoard.string(forType: .string) == "Original clipboard"
        review.copyFormatted()
        results["review_explicit_copy"] = reviewBoard.string(forType: .string) == "Formatted fixture."
        review.clear()
        results["review_deletion_clears_content"] = review.rawText.isEmpty && review.formattedText.isEmpty
        reviewBoard.releaseGlobally()
        do {
            let controller = DictationController(ephemeral: true)
            let owned = controller.sessions.prepare()
            _ = controller.sessions.transition(.processing, session: owned)
            let work = Task<Void, Never> { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            controller.activeTask = work
            controller.start()
            results["new_press_preserves_processing_identity"] = controller.sessions.id == owned && controller.sessions.phase == .processing
            results["new_press_does_not_cancel_transcription"] = !work.isCancelled
            controller.setSuspended(true)
            results["sleep_cancels_owned_work"] = work.isCancelled && controller.sessions.id == nil && !controller.indicator.panel.isVisible
            controller.setSuspended(false)
            results["resume_stays_idle_without_microphone"] = controller.sessions.phase == .idle && !controller.microphone.isCapturing && !controller.indicator.panel.isVisible
            controller.setSuspended(true)
        }
        do {
            var pauses = 0
            let controller = DictationController(ephemeral: true, pauseMedia: { pauses += 1; return true })
            controller.toggle(); controller.cancel()
            await Task.yield()
            results["cancel_before_preparation_sends_no_pause"] = pauses == 0
            pauses = 0
            controller.toggle()
            await Task.yield()
            results["toggle_requests_media_pause_before_capture"] = pauses == 1 && !controller.microphone.isCapturing
            controller.cancel()
            try? await Task.sleep(nanoseconds: 200_000_000)
            results["cancel_during_media_pause_cannot_start_microphone"] = controller.sessions.phase == .cancelled && !controller.microphone.isCapturing
            controller.hotkeys.hold?(true)
            await Task.yield()
            results["hold_requests_media_pause"] = pauses == 2
            controller.hotkeys.hold?(false)
            try? await Task.sleep(nanoseconds: 200_000_000)
            results["hold_release_during_media_pause_stays_stopped"] = controller.sessions.phase == .cancelled && !controller.microphone.isCapturing
            controller.preferences.pauseMedia = false
            controller.toggle(); await Task.yield()
            results["disabled_media_pause_sends_no_command"] = pauses == 2
            controller.setSuspended(true)
            controller.start(); await Task.yield()
            results["suspended_session_does_not_pause_media"] = pauses == 2
            let unavailable = DictationController(ephemeral: true, pauseMedia: { false })
            unavailable.start(); await Task.yield()
            results["failed_pause_dispatch_is_not_reported_as_success"] = unavailable.mediaPauseStatus == "unavailable"
            unavailable.setSuspended(true)
            try? await Task.sleep(nanoseconds: 200_000_000)
            results["sleep_during_media_pause_stays_stopped"] = !unavailable.microphone.isCapturing && unavailable.isSuspended
        }
        let links = ["Privacy_Microphone", "Privacy_Accessibility", "Privacy_ListenEvent"]
        for link in links {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + link) { results["settings_handler_" + link] = NSWorkspace.shared.urlForApplication(toOpen: url) != nil }
        }
        return ["passed":results.values.allSatisfy { $0 }, "checks":results, "indicator_paint_dispatch_ms":elapsed, "indicator_frame_median_ms":frameMedian, "fixture_pipeline_ms":pipelineTimes, "fixture_cleanup":withCleanup, "fixture_model_uses":modelUses, "scope":"App-owned text controls and named clipboard. No microphone or cross-application grant is exercised."]
    }

    private static func shortcutGestures() async -> [String: Bool] {
        let shortcuts = Hotkeys()
        shortcuts.configure(keyCode: UInt32(kVK_F20))
        var actions: [String] = []
        shortcuts.toggle = { actions.append("toggle") }
        shortcuts.command = { actions.append("edit") }
        shortcuts.pasteLast = { actions.append("paste") }
        shortcuts.cancel = { actions.append("cancel") }
        shortcuts.hold = { actions.append($0 ? "hold" : "release") }
        shortcuts.holdInterrupted = { actions.append("interrupt") }
        var results: [String: Bool] = [:]

        func key(_ code: Int, _ flags: CGEventFlags = [], kind: CGEventType = .flagsChanged) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: kind != .keyUp) else {
                results["shortcut_keyboard_fixture"] = false
                return
            }
            event.type = kind
            event.flags = flags
            shortcuts.handleHoldEvent(kind, event: event)
        }
        func carbon(_ binding: Hotkeys.Shortcut, _ kind: Int) {
            guard let id = shortcuts.eventID(for: binding), sendHotKey(id, kind) == noErr else {
                results["shortcut_carbon_fixture"] = false
                return
            }
        }
        func waitForHold() async { try? await Task.sleep(nanoseconds: 240_000_000) }
        func drainActions() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }

        let option = CGEventFlags.maskAlternate.union(CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK)))
        let control = CGEventFlags.maskControl.union(CGEventFlags(rawValue: UInt64(NX_DEVICERCTLKEYMASK)))
        shortcuts.enableHold(true, key: .rightOption)
        key(kVK_RightOption, option)
        key(kVK_RightControl, option.union(control))
        carbon(.toggle, kEventHotKeyPressed)
        carbon(.toggle, kEventHotKeyReleased)
        await waitForHold()
        results["shortcut_option_first_only_toggles"] = actions == ["toggle"]
        key(kVK_RightOption, control)

        actions = []
        key(kVK_RightOption, option.union(control))
        carbon(.command, kEventHotKeyPressed)
        carbon(.command, kEventHotKeyReleased)
        await waitForHold()
        results["shortcut_control_first_only_edits"] = actions == ["edit"]
        key(kVK_RightOption)

        actions = []
        key(kVK_RightOption, option)
        key(kVK_ANSI_E, option, kind: .keyDown)
        await waitForHold()
        results["shortcut_option_typing_does_not_record"] = actions.isEmpty
        key(kVK_RightOption)

        actions = []
        key(kVK_RightOption, option)
        await waitForHold()
        key(kVK_RightOption)
        await drainActions()
        results["shortcut_solo_hold_releases_once"] = actions == ["hold", "release"]

        actions = []
        key(kVK_RightOption, option)
        await waitForHold()
        carbon(.pasteLast, kEventHotKeyPressed)
        carbon(.pasteLast, kEventHotKeyReleased)
        key(kVK_RightOption)
        await drainActions()
        results["shortcut_chord_interrupts_owned_hold_first"] = actions == ["hold", "interrupt", "paste"]

        actions = []
        key(kVK_RightOption, option)
        await drainActions()
        shortcuts.suspend()
        shortcuts.resume()
        await waitForHold()
        results["shortcut_sleep_discards_pending_hold"] = actions.isEmpty

        actions = []
        carbon(.toggle, kEventHotKeyPressed)
        carbon(.toggle, kEventHotKeyPressed)
        carbon(.toggle, kEventHotKeyReleased)
        carbon(.toggle, kEventHotKeyPressed)
        carbon(.toggle, kEventHotKeyReleased)
        await drainActions()
        results["shortcut_one_action_per_press"] = actions == ["toggle", "toggle"]

        actions = []
        shortcuts.escape(true)
        if let old = shortcuts.eventID(for: .cancel) {
            carbon(.cancel, kEventHotKeyPressed)
            shortcuts.escape(false)
            shortcuts.escape(true)
            let staleRejected = sendHotKey(old, kEventHotKeyPressed) == OSStatus(eventNotHandledErr)
            carbon(.cancel, kEventHotKeyPressed)
            await drainActions()
            results["shortcut_replaced_escape_ignores_stale_events"] = staleRejected && actions == ["cancel"]
        } else {
            results["shortcut_replaced_escape_ignores_stale_events"] = false
        }
        return results
    }

    private static func sendHotKey(_ identity: EventHotKeyID, _ kind: Int) -> OSStatus {
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), GetCurrentEventTime(), UInt32(kEventAttributeNone), &event)
        guard created == noErr, let event else { return created }
        defer { ReleaseEvent(event) }
        var identity = identity
        let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identity)
        guard parameter == noErr else { return parameter }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}

#endif
