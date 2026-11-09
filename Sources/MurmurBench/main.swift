import Foundation
import AVFoundation
import Speech
import MurmurCore

let args = CommandLine.arguments
func option(_ key: String) -> String? { guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }; return args[i + 1] }
func emit(_ object: [String: Any]) { if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) } }
func emitEncodable<T: Encodable>(_ object: T) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; print(String(decoding: try encoder.encode(object), as: UTF8.self)) }
var status: Int32 = 0
let gate = DispatchSemaphore(value: 0)
Task {
    do {
        if args.contains("--probe") {
            let locales = await SpeechTranscriber.installedLocales
            emit(["status":"ok", "installed_locales":locales.map(\.identifier), "microphone_authorized":AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "legacy_speech_authorized":SFSpeechRecognizer.authorizationStatus() == .authorized, "local_cleanup_available":SystemCleanup.available])
        } else if let suite = option("--qualify-cleanup") {
            let cases = try JSONDecoder().decode([CleanupFixture].self, from: Data(contentsOf: URL(fileURLWithPath: suite)))
            let report = try await CleanupValidation.run(cases)
            if let path = option("--report") { try JSONEncoder().encode(report).write(to: URL(fileURLWithPath: path), options: .atomic) }
            if args.contains("--save-qualification") { try report.qualification.save() }
            try emitEncodable(report)
        } else if let raw = option("--cleanup") {
            try emitEncodable(await SystemCleanup().attempt(raw, context: TextContext()))
        } else if let instruction = option("--rewrite"), let selected = option("--selected"), let decoder = option("--decoder"), let model = option("--model") {
            let start = Date()
            let edit = try await CommandRewrite(executable: URL(fileURLWithPath: decoder), model: URL(fileURLWithPath: model)).rewrite(instruction: instruction, selected: selected)
            let text: String
            switch edit {
            case .replacement(let replacement): text = replacement
            case .suggestion(let suggestion): text = suggestion
            }
            emit(["status":"ok", "seconds":Date().timeIntervalSince(start), "text":text])
        } else if let file = option("--file") {
            let frames = try AudioTools.readFile(URL(fileURLWithPath: file))
            let provider: any SpeechProvider
            switch option("--engine") {
            case "legacy": provider = LegacySystemSpeechProvider()
            case "analyzer": provider = SystemSpeechProvider()
            default:
                if let decoder = option("--decoder"), let model = option("--model") { provider = ExecutableSpeechProvider(executable: URL(fileURLWithPath: decoder), model: URL(fileURLWithPath: model), useGPU: !args.contains("--cpu"), privateProtocol: args.contains("--private-protocol")) }
                else { provider = SystemSpeechProvider() }
            }
            var vocabulary: [String] = []
            if let path = option("--vocabulary-file") {
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
                let data = try handle.read(upToCount: 65537) ?? Data()
                guard data.count <= 65536 else { throw MurmurError.unavailable("Vocabulary fixture exceeds 64 KiB.") }
                vocabulary = SpeechRequest.vocabulary(String(decoding: data, as: UTF8.self).components(separatedBy: .newlines))
            }
            let result = try await provider.transcribe(frames, language: option("--language") ?? "en-US", vocabulary: vocabulary)
            let cleaned = RuleCleanup().apply(result.text, context: TextContext(dictionary: vocabulary))
            emit(["status":"ok", "provider":provider.name, "audio_seconds":Double(frames.flatMap(\.samples).count) / AudioTools.rate, "recognition_seconds":result.seconds, "text":result.text, "cleaned":cleaned])
        } else { throw MurmurError.unavailable("Use --file, --probe, --qualify-cleanup, --cleanup, or --rewrite.") }
    } catch { status = 1; emit(["status":"unavailable", "reason":error.localizedDescription]) }
    gate.signal()
}
while gate.wait(timeout: .now()) != .success { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
exit(status)
