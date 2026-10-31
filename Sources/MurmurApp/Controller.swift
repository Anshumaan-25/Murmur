import AppKit
import AVFoundation
import MurmurCore

@MainActor final class DictationController {
    let indicator = Indicator()
    var sessions = SessionGate()
    var lastLevelUpdate = Date.distantPast
    let microphone = Microphone()
    let hotkeys = Hotkeys()
    let inserter = ClipboardInserter()
    var destination: Destination?
    var preferences = Preferences.load()
    var history: HistoryStore?
    var status: ((String) -> Void)?
    var received: ((String) -> Void)?
    var changed: (() -> Void)?
    var activeTask: Task<Void, Never>?
    var began = Date()
    var lastSpeech = Date()
    var hadVoice = false
    var timer: Timer?
    var lastText = ""
    var commandMode = false
    let modelPassValidated = false
    func announce(_ text: String) { status?(text); indicator.show(text, phase: sessions.phase) }
    var provider: any SpeechProvider {
        let resources = Bundle.main.resourceURL!
        let customModel = preferences.customSpeechModel
        let customExecutable = preferences.customSpeechExecutable
        let executable = customExecutable.isEmpty ? resources.appendingPathComponent("speech-decode") : URL(fileURLWithPath: customExecutable)
        let model = customModel.isEmpty ? resources.appendingPathComponent("speech-model.bin") : URL(fileURLWithPath: customModel)
        if FileManager.default.isExecutableFile(atPath: executable.path), FileManager.default.fileExists(atPath: model.path) { return ExecutableSpeechProvider(executable: executable, model: model) }
        return SystemSpeechProvider()
    }
    init() {
        do {
            try FileManager.default.createDirectory(at: Preferences.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            history = try HistoryStore(path: Preferences.directory.appendingPathComponent("history.sqlite").path)
            try history?.prune(preferences.retention)
            lastText = try history?.records().first?.cleaned ?? ""
        } catch { status?("Local history is unavailable.") }
        hotkeys.toggle = { [weak self] in self?.toggle() }
        hotkeys.cancel = { [weak self] in self?.cancel() }
        hotkeys.command = { [weak self] in self?.start(command: true) }
        hotkeys.pasteLast = { [weak self] in self?.pasteLast() }
        hotkeys.hold = { [weak self] down in if down { self?.start() } else { self?.finish() } }
        microphone.level = { [weak self] value in DispatchQueue.main.async {
            guard let self, self.sessions.phase == .listening else { return }
            if value > 0.008 { self.lastSpeech = Date(); self.hadVoice = true }
            guard Date().timeIntervalSince(self.lastLevelUpdate) > 0.025 else { return }
            self.lastLevelUpdate = Date(); self.indicator.level(value)
        } }
        applyPreferences()
    }
    func applyPreferences() {
        microphone.inputDevice = preferences.microphone
        hotkeys.enableHold(preferences.holdEnabled)
        hotkeys.configure(keyCode: preferences.toggleKey)
        UserDefaults.standard.set(preferences.holdEnabled, forKey: "holdEnabled")
        do { try preferences.save(); try history?.prune(preferences.retention) } catch { announce("Could not save local preferences.") }
    }
    func toggle() { if sessions.phase == .listening { finish() } else { start() } }
    func start(command: Bool = false) {
        guard sessions.phase != .inserting && sessions.phase != .listening else { return }
        let target = Destination.capture()
        guard !target.protected else { announce("Protected fields cannot receive dictation."); return }
        if command && target.selectedText.isEmpty { announce("Select text before starting an editing command."); return }
        activeTask?.cancel(); sessions.cancel(); destination = target; commandMode = command
        let identity = sessions.begin(); began = Date(); lastSpeech = Date(); hadVoice = false
        announce(command ? "Speak your edit…" : "Listening…"); hotkeys.escape(true)
        do {
            try microphone.start()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.sessions.phase == .listening else { return }
                    if RecordingPolicy.shouldFinish(duration: Date().timeIntervalSince(self.began), silence: Date().timeIntervalSince(self.lastSpeech), heardSpeech: self.hadVoice, handsFree: self.preferences.handsFree, silenceLimit: self.preferences.silenceSeconds, maximum: self.preferences.maximumSeconds) { self.finish() }
                }
            }
        } catch { _ = sessions.transition(.failed, session: identity); announce(error.localizedDescription); hotkeys.escape(false) }
    }
    func finish() {
        guard sessions.phase == .listening, let identity = sessions.id else { return }
        timer?.invalidate(); timer = nil
        let duration = Date().timeIntervalSince(began)
        let frames = AudioTools.trimmed(microphone.stop()); _ = sessions.transition(.processing, session: identity)
        let released = Date(); let target = destination; let editing = commandMode; let prefs = preferences
        announce("Recognizing locally…")
        let selected = provider
        var vocabulary = (try? history?.dictionary()) ?? []
        if prefs.contextEnabled, let target, !target.protected {
            let words = (target.selectedText + " " + (target.value ?? "")).split(whereSeparator: { !$0.isLetter })
            vocabulary += Array(Set(words.filter { $0.count > 2 && $0.first?.isUppercase == true }.map(String.init))).sorted().prefix(24)
        }
        let expansions = (try? history?.values(table: "expansions")) ?? [:]
        let styles = (try? history?.values(table: "app_styles")) ?? [:]
        let app = target?.bundle ?? ""
        let context = TextContext(application: app, style: WritingStyle(rawValue: styles[app] ?? "neutral") ?? .neutral, dictionary: vocabulary, expansions: expansions, selected: prefs.contextEnabled ? target?.selectedText ?? "" : "", surrounding: prefs.contextEnabled ? String((target?.value ?? "").prefix(3000)) : "")
        if prefs.keepAudio {
            let directory = Preferences.directory.appendingPathComponent("Recordings")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? AudioTools.wav(frames).write(to: directory.appendingPathComponent(identity.uuidString + ".wav"), options: .atomic)
        }
        activeTask = Task {
            do {
                guard !frames.isEmpty else { throw MurmurError.empty }
                let result = try await selected.transcribe(frames, language: prefs.language, vocabulary: vocabulary)
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
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
                    cleaned = try await CommandRewrite(executable: available ? executable : nil, model: available ? model : nil).rewrite(instruction: raw, selected: target?.selectedText ?? "")
                }
                else { cleaned = RuleCleanup().apply(raw, context: context) }
                guard !cleaned.isEmpty else { throw MurmurError.empty }
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                _ = sessions.transition(.inserting, session: identity)
                lastText = cleaned; received?(cleaned)
                var outcome = ClipboardInserter.Outcome.copied
                if let target { outcome = try await inserter.insert(cleaned, destination: target, delay: prefs.clipboardDelay, pressReturn: pressReturn, requireSelection: editing) }
                guard sessions.accepts(identity) else { return }
                let record = Utterance(id: identity, application: app, duration: duration, raw: result.text, cleaned: cleaned, inserted: outcome == .inserted ? cleaned : "", outcome: outcome.rawValue, latency: Date().timeIntervalSince(released))
                do { try history?.save(record, retention: prefs.retention) } catch { status?("Text delivered; history could not be saved.") }
                _ = sessions.transition(.idle, session: identity); announce(outcome == .inserted ? "Inserted" : "Copied — check destination"); hotkeys.escape(false); changed?()
            } catch {
                guard sessions.accepts(identity) else { return }
                _ = sessions.transition(.failed, session: identity); announce(error.localizedDescription); hotkeys.escape(false)
            }
        }
    }
    func pasteLast() {
        guard !lastText.isEmpty, sessions.phase != .listening && sessions.phase != .processing && sessions.phase != .inserting else { return }
        let target = Destination.capture(); let text = lastText
        Task { do { let result = try await inserter.insert(text, destination: target, delay: preferences.clipboardDelay); announce(result == .inserted ? "Inserted previous text" : "Previous text copied") } catch { announce(error.localizedDescription) } }
    }
    func cancel() { timer?.invalidate(); timer = nil; activeTask?.cancel(); microphone.cancel(); inserter.finishRestoration(); sessions.cancel(); hotkeys.escape(false); announce("Cancelled") }
}
