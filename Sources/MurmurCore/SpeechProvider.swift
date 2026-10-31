import Foundation
import AVFoundation
import Speech

public struct SpeechResult: Sendable { public let text: String; public let seconds: Double; public init(text: String, seconds: Double) { self.text = text; self.seconds = seconds } }
public enum SpeechUpdate: Sendable { case partial(String), final(SpeechResult) }
public protocol SpeechProvider: Sendable {
    var name: String { get }
    func transcribe(_ audio: [AudioFrame], language: String, vocabulary: [String]) async throws -> SpeechResult
}
public extension SpeechProvider {
    func updates(_ audio: [AudioFrame], language: String, vocabulary: [String]) -> AsyncThrowingStream<SpeechUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { do { continuation.yield(.final(try await transcribe(audio, language: language, vocabulary: vocabulary))); continuation.finish() } catch { continuation.finish(throwing: error) } }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
public struct SystemSpeechProvider: SpeechProvider {
    public let name = "System speech"
    public init() {}
    public func transcribe(_ audio: [AudioFrame], language: String = "en-US", vocabulary: [String] = []) async throws -> SpeechResult {
        let began = Date(); try Task.checkCancellation()
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { throw MurmurError.unavailable("This language is not supported by system speech.") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw MurmurError.unavailable("Install this language in macOS speech settings, or select a downloaded decoder. Murmur will not download assets automatically.") }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext(); context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let resultTask = Task { () throws -> String in
            var segments: [String] = []
            for try await result in transcriber.results { segments.append(String(result.text.characters)) }
            return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw MurmurError.invalidAudio }
            let pcm = try AudioTools.buffer(audio.flatMap(\.samples), format: format)
            let input = AsyncStream<AnalyzerInput> { c in c.yield(AnalyzerInput(buffer: pcm)); c.finish() }
            try await analyzer.start(inputSequence: input)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await resultTask.value; try Task.checkCancellation()
            guard !text.isEmpty else { throw MurmurError.empty }
            return SpeechResult(text: text, seconds: Date().timeIntervalSince(began))
        } catch { resultTask.cancel(); await analyzer.cancelAndFinishNow(); throw error }
    }
}
public struct ExecutableSpeechProvider: SpeechProvider {
    public let name = "Downloaded speech"
    public var executable: URL
    public var model: URL
    public init(executable: URL, model: URL) { self.executable = executable; self.model = model }
    public func transcribe(_ audio: [AudioFrame], language: String, vocabulary: [String]) async throws -> SpeechResult {
        let start = Date()
        var arguments = ["-m", model.path, "-f", "-", "-nt", "-np", "-otxt", "-of", "-", "-l", language.hasPrefix("en") ? "en" : language]
        if !vocabulary.isEmpty { arguments += ["--prompt", vocabulary.joined(separator: ", ")] }
        let output = try await LocalProcess.run(executable: executable, arguments: arguments, input: AudioTools.wav(audio), timeout: 60)
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MurmurError.empty }
        return SpeechResult(text: text, seconds: Date().timeIntervalSince(start))
    }
}
public enum LocalProcess {
    public static func run(executable: URL, arguments: [String], input: Data, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(); let source = Pipe(); let destination = Pipe()
                process.executableURL = executable; process.arguments = arguments
                process.standardInput = source; process.standardOutput = destination; process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    DispatchQueue.global().async { do { try source.fileHandleForWriting.write(contentsOf: input) } catch {} ; try? source.fileHandleForWriting.close() }
                    let output = destination.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); deadline.cancel()
                    guard process.terminationStatus == 0 else { throw MurmurError.unavailable("Local decoder failed or reached its deadline.") }
                    continuation.resume(returning: String(data: output, encoding: .utf8) ?? "")
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
