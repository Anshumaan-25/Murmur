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
    var status: ((String) -> Void)?
    func announce(_ text: String) { status?(text); indicator.show(text, phase: sessions.phase) }
    var received: ((String) -> Void)?
    var activeTask: Task<Void, Never>?
    var began = Date()
    var lastText = ""
    var provider: any SpeechProvider {
        let resources = Bundle.main.resourceURL!
        let executable = resources.appendingPathComponent("speech-decode")
        let model = resources.appendingPathComponent("speech-model.bin")
        if FileManager.default.isExecutableFile(atPath: executable.path), FileManager.default.fileExists(atPath: model.path) { return ExecutableSpeechProvider(executable: executable, model: model) }
        return SystemSpeechProvider()
    }
    init() {
        hotkeys.toggle = { [weak self] in self?.toggle() }
        hotkeys.cancel = { [weak self] in self?.cancel() }
        hotkeys.hold = { [weak self] down in if down { self?.start() } else { self?.finish() } }
        microphone.level = { [weak self] value in DispatchQueue.main.async {
            guard let self, Date().timeIntervalSince(self.lastLevelUpdate) > 0.025 else { return }
            self.lastLevelUpdate = Date(); self.indicator.level(value)
        } }
        hotkeys.enableHold(UserDefaults.standard.object(forKey: "holdEnabled") as? Bool ?? true)
    }
    func toggle() { if sessions.phase == .listening { finish() } else { start() } }
    func start() {
        guard sessions.phase != .inserting else { return }
        activeTask?.cancel(); sessions.cancel()
        destination = Destination.capture()
        let identity = sessions.begin(); began = Date(); announce("Listening…"); hotkeys.escape(true)
        do { try microphone.start() } catch { _ = sessions.transition(.failed, session: identity); announce(error.localizedDescription); hotkeys.escape(false) }
    }
    func finish() {
        guard sessions.phase == .listening, let identity = sessions.id else { return }
        let frames = AudioTools.trimmed(microphone.stop()); _ = sessions.transition(.processing, session: identity)
        announce("Recognizing on this Mac…")
        let selected = provider
        activeTask = Task {
            do {
                guard !frames.isEmpty else { throw MurmurError.empty }
                let result = try await selected.transcribe(frames, language: "en-US", vocabulary: [])
                guard !Task.isCancelled, sessions.accepts(identity) else { return }
                _ = sessions.transition(.inserting, session: identity)
                lastText = result.text; received?(result.text)
                if let destination {
                    let outcome = try await inserter.insert(result.text, destination: destination)
                    guard sessions.accepts(identity) else { return }
                    announce(outcome == .inserted ? "Inserted" : "Copied — destination changed or insertion permission is missing")
                }
                _ = sessions.transition(.idle, session: identity); indicator.show("Ready", phase: .idle); hotkeys.escape(false)
            } catch { guard sessions.accepts(identity) else { return }; _ = sessions.transition(.failed, session: identity); announce(error.localizedDescription); hotkeys.escape(false) }
        }
    }
    func cancel() { activeTask?.cancel(); microphone.cancel(); inserter.finishRestoration(); sessions.cancel(); hotkeys.escape(false); announce("Cancelled") }
}
