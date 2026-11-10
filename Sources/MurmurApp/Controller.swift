import AppKit
import AVFoundation
import MurmurCore

@MainActor final class DictationController {
    let indicator = Indicator()
    var sessions = SessionGate()
    let microphone = Microphone()
    private let pauseMediaRequest: () -> Bool
    private let captureStartOverride: (() throws -> Void)?
    private let captureAuthorized: () -> Bool
    private(set) var mediaPauseStatus = "not_requested"
    let hotkeys = Hotkeys()
    let inserter = ClipboardInserter()
    var destination: Destination?
    var focusContinuity: FocusContinuity?
    var preferences: Preferences
    var history: HistoryStore?
    var status: ((String) -> Void)?
    var phaseChanged: ((CapturePhase) -> Void)?
    var trace = SessionTrace()
    private var drawingSession: UUID?
    private var lastSignal: AudioSignal?
    var received: ((String) -> Void)?
    var changed: (() -> Void)?
    var activeTask: Task<Void, Never>?
    var validationTask: Task<Void, Never>?
    var validationChanged: (() -> Void)?
    var began = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    var retentionTimer: Timer?
    var lastText = ""
    private var lastRaw = ""
    private var lastOutcome = ""
    private var reviewWindow: ResultReviewController?
    private var reviewedHistoryID: UUID?
    private var suggestionWindow: ResultReviewController?
    private let ephemeral: Bool
    private var practiceWindow: ResultReviewController?
    private var practicing = false
    private var lastHistoryID: UUID?
    private var pastingHistoryID: UUID?
    private var suggestedEdit: (id: UUID, text: String, original: String)?
    var commandMode = false
    var holdSession: UUID?
    private(set) var intent = UUID()
    private(set) var isSuspended = false
    private var dictationActivity: NSObjectProtocol?
    var hasDictationActivity: Bool { dictationActivity != nil }
    var measurements = SessionMeasurements()
    var shortcutTitle: String { preferences.toggleKey == 2 ? "Control Option D" : "Control Option Space" }
    var shortcutSymbols: String { preferences.toggleKey == 2 ? "⌃  ⌥  D" : "⌃  ⌥  Space" }
    var modelPassValidated: Bool { CleanupQualification.load()?.eligible == true && SystemCleanup.available }
    func announce(_ text: String) { status?(text); phaseChanged?(sessions.phase); indicator.show(text, phase: sessions.phase) }
    var provider: any SpeechProvider {
        if preferences.speechEngine == .systemAnalyzer { return SystemSpeechProvider() }
        if preferences.speechEngine == .systemLegacy { return LegacySystemSpeechProvider() }
        let resources = Bundle.main.resourceURL!
        let bundledExecutable = resources.appendingPathComponent("speech-decode")
        let bundledModel = resources.appendingPathComponent("speech-model.bin")
        if preferences.speechEngine == .custom {
            guard let approval = preferences.decoderApproval, !preferences.customSpeechExecutable.isEmpty else {
                return UnavailableSpeechProvider("Select and approve a custom decoder in Settings.")
            }
            let executable = URL(fileURLWithPath: preferences.customSpeechExecutable)
            let model = preferences.customSpeechModel.isEmpty ? bundledModel : URL(fileURLWithPath: preferences.customSpeechModel)
            guard FileManager.default.fileExists(atPath: model.path) else {
                return UnavailableSpeechProvider("Choose an available local speech model.")
            }
            return ExecutableSpeechProvider(executable: executable, model: model, timestampDecoding: false, approval: approval)
        }
        if FileManager.default.isExecutableFile(atPath: bundledExecutable.path), FileManager.default.fileExists(atPath: bundledModel.path) {
            return ExecutableSpeechProvider(executable: bundledExecutable, model: bundledModel, privateProtocol: FileManager.default.fileExists(atPath: resources.appendingPathComponent("speech-protocol.json").path))
        }
        if preferences.speechEngine == .bundled { return UnavailableSpeechProvider("Install the bundled decoder and model, or switch to Automatic.") }
        return SystemSpeechProvider()
    }
    init(ephemeral: Bool = false, pauseMedia: (() -> Bool)? = nil, captureStart: (() throws -> Void)? = nil, captureAuthorized: (() -> Bool)? = nil) {
        pauseMediaRequest = pauseMedia ?? (ephemeral ? { true } : { SystemMediaPause.shared.pause() })
        captureStartOverride = ephemeral ? captureStart : nil
        self.captureAuthorized = ephemeral ? (captureAuthorized ?? { true }) : { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
        self.ephemeral = ephemeral
        preferences = ephemeral ? Preferences() : Preferences.load()
        if ephemeral { preferences.holdEnabled = false; preferences.toggleKey = 90 }
        do {
            if !ephemeral { try PrivateStorage.directory(Preferences.directory) }
            history = try HistoryStore(path: ephemeral ? ":memory:" : Preferences.directory.appendingPathComponent("history.sqlite").path)
            try history?.prune(preferences.retention)
            let latest = try history?.records().first
            lastText = latest?.cleaned ?? ""
            lastRaw = latest?.raw ?? ""
            lastOutcome = latest?.outcome ?? ""
            lastHistoryID = latest?.id
        } catch { status?("Local history is unavailable.") }
        hotkeys.toggle = { [weak self] in guard let self else { return }; self.toggle(triggerUptime: self.hotkeys.lastTriggerUptime) }
        hotkeys.cancel = { [weak self] in self?.cancel() }
        hotkeys.command = { [weak self] in self?.start(command: true) }
        hotkeys.pasteLast = { [weak self] in self?.pasteLast() }
        hotkeys.hold = { [weak self] down in
            guard let self else { return }
            if down {
                let previous = self.sessions.id
                self.start(triggerUptime: self.hotkeys.lastTriggerUptime)
                if [.starting, .listening].contains(self.sessions.phase) && self.sessions.id != previous { self.holdSession = self.sessions.id }
            } else {
                if let owned = self.holdSession, owned == self.sessions.id { self.finish() }
                self.holdSession = nil
            }
        }
        hotkeys.holdInterrupted = { [weak self] in
            guard let self, [.starting, .listening].contains(self.sessions.phase), let owned = self.holdSession, owned == self.sessions.id else { return }
            self.cancel(message: "Hold shortcut interrupted. Start dictation again.")
        }
        microphone.configurationChanged = { [weak self] in
            guard let self, [.starting, .listening].contains(self.sessions.phase) else { return }
            self.cancel(message: "Microphone changed. Start dictation again.")
        }
        indicator.inputLevel = { [weak microphone] in microphone?.meter().rms ?? 0 }
        applyPreferences()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, !self.isSuspended else { return }; self.runRetention() }
        }
        retentionTimer?.tolerance = 300
    }
    private func pruneHistory() throws {
        guard let history else { return }
        // Row deletion may succeed even if an orphan recording could not be removed.
        defer {
            if let id = reviewedHistoryID, (try? history.contains(id)) == false { reviewWindow?.clear(); reviewWindow?.close(); reviewedHistoryID = nil }
            if let id = lastHistoryID, (try? history.contains(id)) == false { clearPrevious(id) }
            changed?()
        }
        try history.prune(preferences.retention)
    }

    private func runRetention() {
        do { try pruneHistory() }
        catch { status?("Some local history or recordings could not be removed.") }
    }

    func clearPrevious(_ id: UUID) {
        if reviewedHistoryID == id { reviewWindow?.clear(); reviewWindow?.close(); reviewedHistoryID = nil }
        guard id == lastHistoryID else { return }
        if pastingHistoryID == id {
            activeTask?.cancel()
            inserter.finishRestoration()
            pastingHistoryID = nil
        }
        lastText = ""; lastRaw = ""; lastOutcome = ""
        reviewWindow?.clear(); reviewWindow?.close(); indicator.recovery(copy: nil, review: nil)
        lastHistoryID = nil
        received?("")
    }

    @discardableResult func applyPreferences() -> Bool {
        microphone.inputDevice = preferences.microphone
        hotkeys.enableHold(preferences.holdEnabled, key: preferences.holdKey)
        hotkeys.configure(keyCode: preferences.toggleKey)
        if ephemeral { return true }
        UserDefaults.standard.set(preferences.holdEnabled, forKey: "holdEnabled")
        do { try preferences.save() }
        catch { announce("Could not save local preferences."); return false }
        do { try pruneHistory() }
        catch { announce("Settings saved, but some local history or recordings could not be removed."); return false }
        return true
    }

    private func persist(_ record: Utterance, frames: [AudioFrame], previous: Bool) throws {
        guard preferences.retention != .never else { return }
        guard let history else { throw MurmurError.unavailable("Local history is unavailable.") }
        try history.save(record, retention: preferences.retention)
        if previous { lastHistoryID = record.id }
        if preferences.keepAudio, !frames.isEmpty { try history.saveRecording(AudioTools.wav(frames), for: record.id) }
    }

    func validateCleanup() {
        guard !isSuspended else { return }
        guard validationTask == nil, ![CapturePhase.starting, .listening, .processing, .inserting].contains(sessions.phase) else { announce("Finish the current task before validation."); return }
        status?("Checking on-device cleanup against the text suite…"); hotkeys.escape(true)
        validationTask = Task {
            defer { validationTask = nil; hotkeys.escape(false); validationChanged?() }
            do {
                let report = try await CleanupValidation.run(CleanupFixture.bundled())
                try Task.checkCancellation(); try report.qualification.save()
                if !report.qualification.eligible { preferences.useModel = false; try preferences.save() }
                status?(report.qualification.eligible ? "Local cleanup passed its quality and timing gates." : "Local cleanup did not qualify; rules remain active.")
            } catch {
                if !isSuspended { status?(error is CancellationError ? "Validation cancelled" : error.localizedDescription) }
            }
        }
    }
    func toggle(triggerUptime: Double? = nil) { intent = UUID(); if [.starting, .listening].contains(sessions.phase) { finish() } else { start(triggerUptime: triggerUptime) } }
    func start(command: Bool = false, triggerUptime: Double? = nil, expectedPID: pid_t? = nil) {
        intent = UUID()
        guard !isSuspended else { return }
        guard validationTask == nil else { announce("Cleanup validation is running. Escape cancels it."); return }
        guard sessions.canStart else { trace.record(.busy, session: sessions.id); announce("Finish this dictation first · Esc cancels it"); return }
        let triggered = triggerUptime ?? ProcessInfo.processInfo.systemUptime
        stopWork()
        commandMode = command
        let identity = sessions.prepare(); began = ProcessInfo.processInfo.systemUptime
        trace.record(.starting, session: identity); drawingSession = nil; lastSignal = nil; indicator.preferredPoint = nil
        indicator.didDraw = { [weak self] in
            guard let self, self.sessions.id == identity, self.drawingSession != identity else { return }
            self.drawingSession = identity
            self.measurements.feedback(trigger: triggered, painted: ProcessInfo.processInfo.systemUptime)
            self.trace.record(.drawDispatched, session: identity)
        }
        indicator.recovery(copy: nil, review: nil)
        announce(command ? "Preparing edit…" : "Starting microphone…")
        practicing = !command && practiceWindow?.window?.isKeyWindow == true
        if !practicing && !ephemeral {
            focusContinuity = FocusContinuity(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, toggleKey: UInt16(clamping: preferences.toggleKey), holdKey: preferences.holdEnabled ? UInt16(preferences.holdKey.code) : nil)
        }
        let target = (practicing || ephemeral) ? Destination(pid: ProcessInfo.processInfo.processIdentifier, bundle: "local.murmur.practice", element: nil, windowElement: nil, value: nil, selection: nil, selectedText: "", protected: false, editable: false, role: "") : Destination.capture()
        guard !target.protected else { focusContinuity?.stop(); _ = sessions.transition(.failed, session: identity); announce("Protected fields cannot receive dictation."); return }
        if command && (!target.editable || target.selectedText.isEmpty || target.selection == nil) { focusContinuity?.stop(); _ = sessions.transition(.failed, session: identity); announce("Select text before starting an editing command."); return }
        if let expectedPID, target.pid != expectedPID || NSWorkspace.shared.frontmostApplication?.processIdentifier != expectedPID {
            focusContinuity?.stop()
            _ = sessions.transition(.failed, session: identity)
            announce("The previous app lost focus. Start dictation again.")
            return
        }
        destination = target; indicator.preferredPoint = target.screenPoint; hotkeys.escape(true)
        dictationActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Keydown dictation")
        let pausePlayback = preferences.pauseMedia
        activeTask = Task {
            do {
                guard !Task.isCancelled, sessions.id == identity, sessions.phase == .starting else { return }
                let maximum = preferences.maximumSeconds
                guard captureAuthorized() else {
                    throw MurmurError.unavailable("Enable Keydown microphone access in System Settings.")
                }
                mediaPauseStatus = "disabled"
                if pausePlayback {
                    let sent = pauseMediaRequest()
                    mediaPauseStatus = sent ? "requested_unconfirmed" : "unavailable"
                    // Let the player process its pause before opening an audio device.
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
                guard !Task.isCancelled, sessions.id == identity, sessions.phase == .starting else { return }
                try beginCapture(maximumSeconds: maximum, onReady: { [weak self] in
                    guard let self, self.sessions.transition(.listening, session: identity) else { return }
                    self.trace.record(.firstSample, session: identity)
                    self.announce(command ? "Speak your edit…" : "Listening…")
                }) { [weak self] in
                    guard let self, self.sessions.id == identity else { return }
                    self.finish()
                }
                let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, [.starting, .listening].contains(self.sessions.phase) else { return }
                        let meter = self.microphone.meter()
                        let now = ProcessInfo.processInfo.systemUptime
                        if (!meter.received && now - self.began > 3) || (meter.received && now - meter.lastBuffer > 2) {
                            self.cancel(message: "Microphone stopped sending audio. Check the input device."); return
                        }
                        if self.sessions.phase == .listening && meter.signal != self.lastSignal && !self.commandMode {
                            self.lastSignal = meter.signal; self.announce(meter.signal.message)
                        }
                        if RecordingPolicy.shouldFinish(
                            duration: ProcessInfo.processInfo.systemUptime - self.began,
                            silence: meter.speechSilence,
                            heardSpeech: meter.heardSpeech,
                            handsFree: self.preferences.handsFree,
                            silenceLimit: self.preferences.silenceSeconds,
                            maximum: maximum,
                            holdToTalk: self.holdSession == self.sessions.id
                        ) { self.finish() }
                    }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            } catch {
                guard !Task.isCancelled, sessions.id == identity else { return }
                focusContinuity?.stop()
                endDictationActivity()
                _ = sessions.transition(.failed, session: identity)
                announce(error.localizedDescription)
                hotkeys.escape(false)
            }
        }
    }
    private func beginCapture(maximumSeconds: Double, onReady: @escaping @MainActor () -> Void, onLimit: @escaping @MainActor () -> Void) throws {
        if ephemeral {
            guard let captureStartOverride else { throw MurmurError.unavailable("Fixture microphone is disabled.") }
            try captureStartOverride()
            onReady()
        } else {
            try microphone.start(maximumSeconds: maximumSeconds, onReady: onReady, onLimit: onLimit)
        }
    }
    func finish() {
        guard !isSuspended, [.starting, .listening].contains(sessions.phase), let identity = sessions.id else { return }
        if sessions.phase == .starting && !microphone.isCapturing {
            cancel(message: "Stopped before microphone was ready"); return
        }
        holdSession = nil
        timer?.invalidate(); timer = nil
        let duration = ProcessInfo.processInfo.systemUptime - began
        let capture = microphone.stop()
        let frames = AudioTools.trimmed(capture.frames); _ = sessions.transition(.processing, session: identity)
        let released = Date(); let releasedUptime = ProcessInfo.processInfo.systemUptime; let initialTarget = destination; let continuity = focusContinuity; let editing = commandMode; let prefs = preferences; let practice = practicing
        trace.record(.processing, session: identity)
        announce("Recognizing locally…")
        let selected = provider
        activeTask = Task {
            defer {
                capture.speech?.cancel()
                continuity?.stop()
                if sessions.id == identity { endDictationActivity() }
            }
            var recognized = ""; var prepared = ""; var app = initialTarget?.bundle ?? ""
            do {
                let target = initialTarget
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                guard target?.protected != true else { throw MurmurError.protectedTarget }
                if editing && (target?.selectedText.isEmpty ?? true) { throw MurmurError.unavailable("Select text before starting an editing command.") }
                var vocabulary = (try? history?.dictionary()) ?? []
                if prefs.contextEnabled, let target, !target.protected {
                    let words = (target.selectedText + " " + (target.value ?? "")).split(whereSeparator: { !$0.isLetter })
                    vocabulary += Array(Set(words.filter { $0.count > 2 && $0.first?.isUppercase == true }.map(String.init))).sorted().prefix(24)
                }
                let expansions = (try? history?.values(table: "expansions")) ?? [:]
                let styles = (try? history?.values(table: "app_styles")) ?? [:]
                app = target?.bundle ?? ""
                let context = TextContext(application: app, preserveCode: prefs.preserveCode, style: WritingStyle(rawValue: styles[app] ?? "neutral") ?? .neutral, dictionary: vocabulary, expansions: expansions, selected: prefs.contextEnabled ? target?.selectedText ?? "" : "", surrounding: prefs.contextEnabled ? String((target?.value ?? "").prefix(3000)) : "", mode: prefs.dictationMode)
                guard !frames.isEmpty else { throw MurmurError.empty }
                let evidence: SpeechEvidence
                if let monitor = capture.speech {
                    evidence = (try? await Deadline.run(seconds: 3) { await monitor.finish() }) ?? SpeechEvidence()
                } else { evidence = SpeechEvidence() }
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                let result = try await selected.transcribe(frames, language: prefs.language, vocabulary: vocabulary)
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                trace.record(.decoded, session: identity)
                recognized = result.text
                let raw = result.text
                if !evidence.allowsAutomaticDelivery {
                    // Do not interpret uncertain audio as an editing command or paste
                    // invented prose. Keep even quiet/short speech available to review.
                    retainUncertain(raw: raw, identity: identity, application: app, duration: duration, frames: frames, practice: practice, editing: editing)
                    return
                }
                let cleaned: String
                if editing {
                    let resources = Bundle.main.resourceURL!
                    let executable = resources.appendingPathComponent("text-complete")
                    let model = resources.appendingPathComponent("editing-model.gguf")
                    let available = FileManager.default.isExecutableFile(atPath: executable.path) && FileManager.default.fileExists(atPath: model.path)
                    announce("Editing locally…")
                    let result = try await CommandRewrite(executable: available ? executable : nil, model: available ? model : nil).rewrite(instruction: raw, selected: target?.selectedText ?? "", protectedTerms: context.dictionary)
                    guard !Task.isCancelled, sessions.accepts(identity) else { return }
                    switch result {
                    case .replacement(let text): cleaned = text
                    case .suggestion(let text):
                        suggestedEdit = (identity, text, target?.selectedText ?? "")
                        _ = sessions.transition(.inserting, session: identity)
                        _ = sessions.transition(.idle, session: identity)
                        hotkeys.escape(false)
                        announce("Suggested edit ready · choose Review Suggested Edit from the menu")
                        return
                    }
                }
                else if prefs.useModel && modelPassValidated { cleaned = try await SystemCleanup().clean(raw, context: context) }
                else { cleaned = RuleCleanup().apply(raw, context: context) }
                guard !cleaned.isEmpty else { throw MurmurError.empty }
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                _ = sessions.transition(.inserting, session: identity)
                trace.record(.cleaned, session: identity)
                prepared = cleaned
                if practice {
                    practiceWindow?.update(raw: raw, cleaned: cleaned, outcome: "Practice only · not saved")
                    _ = sessions.transition(.idle, session: identity); hotkeys.escape(false)
                    announce("Practice result ready in the practice window")
                    return
                }
                var outcome = ClipboardInserter.Outcome.available
                if let target { outcome = try await inserter.insert(cleaned, destination: target, delay: prefs.clipboardDelay, requireSelection: editing, continuity: continuity) }
                guard sessions.accepts(identity) else { return }
                trace.record(outcome == .queued ? .queued : .available, session: identity)
                lastText = cleaned; lastRaw = raw; lastOutcome = outcome.rawValue; lastHistoryID = nil; received?(cleaned)
                reviewWindow?.clear()
                showRecoveryActions()
                if outcome == .queued { measurements.insertion(released: releasedUptime, finished: ProcessInfo.processInfo.systemUptime) }
                let record = Utterance(id: identity, application: app, duration: duration, raw: result.text, cleaned: cleaned, inserted: "", outcome: outcome == .queued ? outcome.rawValue : "available: " + inserter.lastReason.rawValue, latency: Date().timeIntervalSince(released))
                var message = inserter.lastReason.explanation
                do { try persist(record, frames: frames, previous: true) }
                catch { message += " · Some local data could not be saved." }
                _ = sessions.transition(.idle, session: identity); announce(message); hotkeys.escape(false); changed?()
            } catch {
                guard sessions.accepts(identity) else { return }
                var message = error.localizedDescription
                if !recognized.isEmpty && !practice {
                    let recovery = prepared.isEmpty ? recognized : prepared
                    lastText = recovery; lastRaw = recognized; lastOutcome = "Delivery failed · result available"; lastHistoryID = nil
                    reviewWindow?.clear()
                    showRecoveryActions()
                    let failure = Utterance(id: identity, application: app, duration: duration, raw: recognized, cleaned: recovery, inserted: "", outcome: "failed · available for copy", latency: Date().timeIntervalSince(released))
                    do { try persist(failure, frames: [], previous: true) }
                    catch { message += " · History could not be saved." }
                    changed?()
                }
                _ = sessions.transition(.failed, session: identity); announce(message); hotkeys.escape(false)
            }
        }
    }
    func retainUncertain(raw: String, identity: UUID, application: String, duration: Double, frames: [AudioFrame], practice: Bool, editing: Bool) {
        guard sessions.accepts(identity) else { return }
        var message = editing ? "Speech uncertain · edit not applied · review recognized instruction" : "Speech uncertain · review before copying"
        _ = sessions.transition(.inserting, session: identity)
        _ = sessions.transition(.idle, session: identity)
        hotkeys.escape(false)
        if practice {
            practiceWindow?.update(raw: raw, cleaned: raw, outcome: message)
        } else {
            lastRaw = raw; lastText = raw; lastOutcome = message; lastHistoryID = nil
            reviewWindow?.clear(); showRecoveryActions()
            let record = Utterance(id: identity, application: application, duration: duration, raw: raw, cleaned: raw, inserted: "", outcome: message, latency: 0)
            do { try persist(record, frames: frames, previous: true) }
            catch { message += " · History could not be saved." }
            reviewLast()
        }
        announce(message); changed?()
    }
    private func showRecoveryActions() {
        indicator.recovery(copy: { [weak self] in self?.copyLast() }, review: { [weak self] in self?.reviewLast() })
    }
    func pasteLast() {
        intent = UUID()
        guard !isSuspended, !lastText.isEmpty, sessions.canStart else { return }
        activeTask?.cancel()
        focusContinuity?.stop()
        inserter.finishRestoration()
        let continuity = FocusContinuity(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, toggleKey: UInt16(clamping: preferences.toggleKey), holdKey: preferences.holdEnabled ? UInt16(preferences.holdKey.code) : nil)
        focusContinuity = continuity
        let target = Destination.capture()
        let text = lastText
        let request = intent
        pastingHistoryID = lastHistoryID
        activeTask = Task {
            defer {
                if intent == request { pastingHistoryID = nil }
                continuity.stop()
            }
            do {
                try Task.checkCancellation()
                _ = try await inserter.insert(text, destination: target, delay: preferences.clipboardDelay, continuity: continuity)
                try Task.checkCancellation()
                announce(inserter.lastReason.explanation)
            } catch {
                if !Task.isCancelled { announce(error.localizedDescription) }
            }
        }
    }

    func reviewLast() {
        guard !lastText.isEmpty, !isSuspended else { return }
        if reviewWindow == nil { reviewWindow = makeReviewWindow(practice: false) }
        reviewedHistoryID = lastHistoryID
        reviewWindow?.update(raw: lastRaw, cleaned: lastText, outcome: lastOutcome)
        reviewWindow?.present()
    }
    func reviewRecord(_ record: Utterance) {
        guard !isSuspended else { return }
        if reviewWindow == nil { reviewWindow = makeReviewWindow(practice: false) }
        reviewedHistoryID = record.id
        reviewWindow?.update(raw: record.raw, cleaned: record.cleaned, outcome: record.outcome)
        reviewWindow?.present()
    }
    func showPractice() {
        guard !isSuspended, sessions.canStart else { announce("Finish this dictation before opening practice"); return }
        if practiceWindow == nil {
            practiceWindow = makeReviewWindow(practice: true)
            practiceWindow?.practiceAction = { [weak self] in self?.toggle() }
            practiceWindow?.closed = { [weak self] in
                guard let self, self.practicing else { return }; self.cancel(message: "Practice cancelled")
            }
        }
        practiceWindow?.present()
    }
    private func makeReviewWindow(practice: Bool) -> ResultReviewController {
        let view = ResultReviewController(practice: practice)
        view.learnTerm = { [weak self] term in
            guard let history = self?.history else { throw MurmurError.unavailable("Vocabulary storage is unavailable.") }
            var terms = try history.dictionary(); terms.append(term); try history.setDictionary(terms)
        }
        return view
    }

    func reviewSuggestedEdit() {
        guard !isSuspended, let suggestion = suggestedEdit else { announce("No suggested edit is waiting."); return }
        if suggestionWindow == nil { suggestionWindow = makeReviewWindow(practice: false) }
        suggestionWindow?.update(raw: suggestion.original, cleaned: suggestion.text, outcome: "Suggested edit · review wording and facts before copying")
        suggestionWindow?.present()
    }

    func copyLast() {
        intent = UUID()
        guard !isSuspended, !lastText.isEmpty else { return }
        inserter.finishRestoration()
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(lastText, forType: .string) { announce("Copied previous text") }
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            practiceWindow?.clear(); reviewWindow?.close()
            trace.record(.suspended, session: sessions.id)
            hotkeys.suspend()
            stopWork()
            indicator.hide()
            status?("Dictation paused"); phaseChanged?(.idle)
        } else {
            sessions.reset()
            trace.record(.resumed, session: nil)
            indicator.hide(); indicator.preferredPoint = nil
            hotkeys.resume()
            status?("Ready · \(shortcutTitle)")
            runRetention()
        }
    }

    func cancel(message: String = "Cancelled") {
        stopWork()
        if !isSuspended { announce(message) }
    }

    private func stopWork() {
        intent = UUID()
        suggestedEdit = nil
        suggestionWindow?.clear(); suggestionWindow?.close()
        practicing = false
        pastingHistoryID = nil
        trace.record(.cancelled, session: sessions.id)
        sessions.cancel()
        holdSession = nil
        validationTask?.cancel()
        timer?.invalidate()
        timer = nil
        activeTask?.cancel()
        activeTask = nil
        destination = nil
        focusContinuity?.stop()
        focusContinuity = nil
        microphone.cancel()
        inserter.finishRestoration()
        hotkeys.escape(false)
        endDictationActivity()
    }

    private func endDictationActivity() {
        guard let activity = dictationActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        dictationActivity = nil
    }
}
