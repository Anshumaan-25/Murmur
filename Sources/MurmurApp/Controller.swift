import AppKit
import AVFoundation
import MurmurCore

@MainActor final class DictationController {
    var sessions = SessionGate()
    let microphone = Microphone()
    let hotkeys = Hotkeys()
    let inserter = ClipboardInserter()
    var destination: Destination?
    var status: ((String) -> Void)?
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
    }
    func toggle() { if sessions.phase == .listening { finish() } else { start() } }
    func start() {
        guard sessions.phase != .inserting else { return }
        activeTask?.cancel(); sessions.cancel()
        destination = Destination.capture()
        let identity = sessions.begin(); began = Date(); status?("Listening…"); hotkeys.escape(true)
        do { try microphone.start() } catch { _ = sessions.transition(.failed, session: identity); status?(error.localizedDescription); hotkeys.escape(false) }
    }
    func finish() {
        guard sessions.phase == .listening, let identity = sessions.id else { return }
        let frames = AudioTools.trimmed(microphone.stop()); _ = sessions.transition(.processing, session: identity)
        status?("Recognizing on this Mac…")
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
                    status?(outcome == .inserted ? "Inserted" : "Copied — destination changed or insertion permission is missing")
                }
                _ = sessions.transition(.idle, session: identity); hotkeys.escape(false)
            } catch { guard sessions.accepts(identity) else { return }; _ = sessions.transition(.failed, session: identity); status?(error.localizedDescription); hotkeys.escape(false) }
        }
    }
    func cancel() { activeTask?.cancel(); microphone.cancel(); inserter.finishRestoration(); sessions.cancel(); hotkeys.escape(false); status?("Cancelled") }
}
