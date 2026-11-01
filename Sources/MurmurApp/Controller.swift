import AppKit
import AVFoundation
import MurmurCore

@MainActor final class DictationController {
    let indicator = Indicator()
    var sessions = SessionGate()
    let microphone = Microphone()
    let hotkeys = Hotkeys()
    let inserter = ClipboardInserter()
    var destination: Destination?
    var destinationTask: Task<Destination, Error>?
    var focusContinuity: FocusContinuity?
    var preferences = Preferences.load()
    var history: HistoryStore?
    var status: ((String) -> Void)?
    var received: ((String) -> Void)?
    var changed: (() -> Void)?
    var activeTask: Task<Void, Never>?
    var validationTask: Task<Void, Never>?
    var validationChanged: (() -> Void)?
    var began = Date()
    var timer: Timer?
    var retentionTimer: Timer?
    var lastText = ""
    var commandMode = false
    var holdSession: UUID?
    var measurements = SessionMeasurements()
    var shortcutTitle: String { preferences.toggleKey == 2 ? "Control Option D" : "Control Option Space" }
    var modelPassValidated: Bool { CleanupQualification.load()?.eligible == true && SystemCleanup.available }
    func announce(_ text: String) { status?(text); indicator.show(text, phase: sessions.phase) }
    var provider: any SpeechProvider {
        if preferences.speechEngine == .systemAnalyzer { return SystemSpeechProvider() }
        if preferences.speechEngine == .systemLegacy { return LegacySystemSpeechProvider() }
        let resources = Bundle.main.resourceURL!
        let customModel = preferences.customSpeechModel
        let customExecutable = preferences.customSpeechExecutable
        let executable = customExecutable.isEmpty ? resources.appendingPathComponent("speech-decode") : URL(fileURLWithPath: customExecutable)
        let model = customModel.isEmpty ? resources.appendingPathComponent("speech-model.bin") : URL(fileURLWithPath: customModel)
        if FileManager.default.isExecutableFile(atPath: executable.path), FileManager.default.fileExists(atPath: model.path) { return ExecutableSpeechProvider(executable: executable, model: model) }
        if preferences.speechEngine == .bundled { return UnavailableSpeechProvider("Choose a local model and executable, or switch to Automatic.") }
        return SystemSpeechProvider()
    }
    init() {
        do {
            try FileManager.default.createDirectory(at: Preferences.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            history = try HistoryStore(path: Preferences.directory.appendingPathComponent("history.sqlite").path)
            try history?.prune(preferences.retention)
            lastText = try history?.records().first?.cleaned ?? ""
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
                if self.sessions.phase == .listening && self.sessions.id != previous { self.holdSession = self.sessions.id }
            } else {
                if let owned = self.holdSession, owned == self.sessions.id { self.finish() }
                self.holdSession = nil
            }
        }
        indicator.inputLevel = { [weak microphone] in microphone?.meter().rms ?? 0 }
        applyPreferences()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; try? self.history?.prune(self.preferences.retention); self.pruneRecordings() }
        }
    }
    func pruneRecordings() {
        let directory = Preferences.directory.appendingPathComponent("Recordings")
        guard preferences.retention != .forever, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.pathExtension == "wav" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if preferences.retention == .never || created < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
        }
    }
    func applyPreferences() {
        microphone.inputDevice = preferences.microphone
        hotkeys.enableHold(preferences.holdEnabled, key: preferences.holdKey)
        hotkeys.configure(keyCode: preferences.toggleKey)
        UserDefaults.standard.set(preferences.holdEnabled, forKey: "holdEnabled")
        do { try preferences.save(); try history?.prune(preferences.retention); pruneRecordings() } catch { announce("Could not save local preferences.") }
    }
    func validateCleanup() {
        guard validationTask == nil, ![CapturePhase.listening, .processing, .inserting].contains(sessions.phase) else { announce("Finish the current task before validation."); return }
        status?("Checking on-device cleanup against the text suite…"); hotkeys.escape(true)
        validationTask = Task {
            defer { validationTask = nil; hotkeys.escape(false); validationChanged?() }
            do {
                let report = try await CleanupValidation.run(CleanupFixture.bundled())
                try Task.checkCancellation(); try report.qualification.save()
                if !report.qualification.eligible { preferences.useModel = false; try preferences.save() }
                status?(report.qualification.eligible ? "Local cleanup passed its quality and timing gates." : "Local cleanup did not qualify; rules remain active.")
            } catch { status?(error is CancellationError ? "Validation cancelled" : error.localizedDescription) }
        }
    }
    func toggle(triggerUptime: Double? = nil) { if sessions.phase == .listening { finish() } else { start(triggerUptime: triggerUptime) } }
    func start(command: Bool = false, triggerUptime: Double? = nil) {
        guard validationTask == nil else { announce("Cleanup validation is running. Escape cancels it."); return }
        guard sessions.phase != .inserting && sessions.phase != .listening else { return }
        let triggered = triggerUptime ?? ProcessInfo.processInfo.systemUptime
        activeTask?.cancel(); destinationTask?.cancel(); focusContinuity?.stop(); sessions.cancel(); commandMode = command
        let identity = sessions.begin(); began = Date()
        announce(command ? "Preparing edit…" : "Starting microphone…")
        measurements.feedback(trigger: triggered, painted: ProcessInfo.processInfo.systemUptime)
        focusContinuity = FocusContinuity(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, toggleKey: UInt16(clamping: preferences.toggleKey), holdKey: preferences.holdEnabled ? UInt16(preferences.holdKey.code) : nil)
        let target = Destination.capture()
        guard !target.protected else { focusContinuity?.stop(); _ = sessions.transition(.failed, session: identity); announce("Protected fields cannot receive dictation."); return }
        if command && target.selectedText.isEmpty && target.element != nil { focusContinuity?.stop(); _ = sessions.transition(.failed, session: identity); announce("Select text before starting an editing command."); return }
        destination = target; destinationTask = Task { try await Destination.prepared(target) }; hotkeys.escape(true)
        do {
            try microphone.start()
            announce(command ? "Speak your edit…" : "Listening…")
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.sessions.phase == .listening else { return }
                    let meter = self.microphone.meter()
                    if RecordingPolicy.shouldFinish(duration: Date().timeIntervalSince(self.began), silence: ProcessInfo.processInfo.systemUptime - meter.lastVoice, heardSpeech: meter.lastVoice > 0, handsFree: self.preferences.handsFree, silenceLimit: self.preferences.silenceSeconds, maximum: self.preferences.maximumSeconds) { self.finish() }
                }
            }
        } catch { destinationTask?.cancel(); focusContinuity?.stop(); _ = sessions.transition(.failed, session: identity); announce(error.localizedDescription); hotkeys.escape(false) }
    }
    func finish() {
        guard sessions.phase == .listening, let identity = sessions.id else { return }
        timer?.invalidate(); timer = nil
        let duration = Date().timeIntervalSince(began)
        let frames = AudioTools.trimmed(microphone.stop()); _ = sessions.transition(.processing, session: identity)
        let released = Date(); let releasedUptime = ProcessInfo.processInfo.systemUptime; let initialTarget = destination; let pendingDestination = destinationTask; let continuity = focusContinuity; let editing = commandMode; let prefs = preferences
        announce("Recognizing locally…")
        let selected = provider
        if prefs.keepAudio && prefs.retention != .never {
            let directory = Preferences.directory.appendingPathComponent("Recordings")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? AudioTools.wav(frames).write(to: directory.appendingPathComponent(identity.uuidString + ".wav"), options: .atomic)
        }
        activeTask = Task {
            defer { continuity?.stop() }
            var recognized = ""; var prepared = ""; var app = initialTarget?.bundle ?? ""
            do {
                let target: Destination?
                if let pendingDestination { target = try await pendingDestination.value } else { target = initialTarget }
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
                let context = TextContext(application: app, preserveCode: prefs.preserveCode, style: WritingStyle(rawValue: styles[app] ?? "neutral") ?? .neutral, dictionary: vocabulary, expansions: expansions, selected: prefs.contextEnabled ? target?.selectedText ?? "" : "", surrounding: prefs.contextEnabled ? String((target?.value ?? "").prefix(3000)) : "")
                guard !frames.isEmpty else { throw MurmurError.empty }
                let result = try await selected.transcribe(frames, language: prefs.language, vocabulary: vocabulary)
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                recognized = result.text
                var raw = result.text
                var pressReturn = false
                let intent = RecordingPolicy.returnIntent(raw, enabled: prefs.spokenReturn && !editing)
                raw = intent.text; pressReturn = intent.pressReturn
                let cleaned: String
                if editing {
                    let resources = Bundle.main.resourceURL!
                    let executable = resources.appendingPathComponent("text-complete")
                    let model = resources.appendingPathComponent("editing-model.gguf")
                    let available = FileManager.default.isExecutableFile(atPath: executable.path) && FileManager.default.fileExists(atPath: model.path)
                    announce("Editing locally…")
                    cleaned = try await CommandRewrite(executable: available ? executable : nil, model: available ? model : nil).rewrite(instruction: raw, selected: target?.selectedText ?? "", protectedTerms: context.dictionary)
                }
                else if prefs.useModel && modelPassValidated { cleaned = try await SystemCleanup().clean(raw, context: context) }
                else { cleaned = RuleCleanup().apply(raw, context: context) }
                guard !cleaned.isEmpty else { throw MurmurError.empty }
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                _ = sessions.transition(.inserting, session: identity)
                prepared = cleaned
                lastText = cleaned; received?(cleaned)
                var outcome = ClipboardInserter.Outcome.copied
                if let target { outcome = try await inserter.insert(cleaned, destination: target, delay: prefs.clipboardDelay, pressReturn: pressReturn, requireSelection: editing, continuity: continuity) }
                guard sessions.accepts(identity) else { return }
                if outcome == .inserted { measurements.insertion(released: releasedUptime, finished: ProcessInfo.processInfo.systemUptime) }
                let record = Utterance(id: identity, application: app, duration: duration, raw: result.text, cleaned: cleaned, inserted: outcome == .inserted ? cleaned : "", outcome: outcome == .inserted ? outcome.rawValue : "copied: " + inserter.lastReason.rawValue, latency: Date().timeIntervalSince(released))
                do { try history?.save(record, retention: prefs.retention) } catch { status?("Text delivered; history could not be saved.") }
                _ = sessions.transition(.idle, session: identity); announce(outcome == .inserted ? "Inserted" : inserter.lastReason.explanation); hotkeys.escape(false); changed?()
            } catch {
                guard sessions.accepts(identity) else { return }
                if !recognized.isEmpty {
                    let failure = Utterance(id: identity, application: app, duration: duration, raw: recognized, cleaned: prepared, inserted: "", outcome: "failed", latency: Date().timeIntervalSince(released))
                    try? history?.save(failure, retention: prefs.retention); changed?()
                }
                _ = sessions.transition(.failed, session: identity); announce(error.localizedDescription); hotkeys.escape(false)
            }
        }
    }
    func pasteLast() {
        guard !lastText.isEmpty, sessions.phase != .listening && sessions.phase != .processing && sessions.phase != .inserting else { return }
        let continuity = FocusContinuity(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, toggleKey: UInt16(clamping: preferences.toggleKey), holdKey: preferences.holdEnabled ? UInt16(preferences.holdKey.code) : nil)
        let target = Destination.capture(); let text = lastText
        Task { defer { continuity.stop() }; do { let resolved = try await Destination.prepared(target); let result = try await inserter.insert(text, destination: resolved, delay: preferences.clipboardDelay, continuity: continuity); announce(result == .inserted ? "Inserted previous text" : inserter.lastReason.explanation) } catch { announce(error.localizedDescription) } }
    }
    func cancel() { validationTask?.cancel(); timer?.invalidate(); timer = nil; activeTask?.cancel(); destinationTask?.cancel(); focusContinuity?.stop(); microphone.cancel(); inserter.finishRestoration(); sessions.cancel(); hotkeys.escape(false); announce("Cancelled") }
}
