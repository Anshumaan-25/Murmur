import Foundation
import AVFoundation
import Speech
import Darwin

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
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw MurmurError.unavailable("Install this language in macOS speech settings, or select a downloaded decoder. Keydown will not download assets automatically.") }
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
    public var useGPU: Bool
    private let timestampDecoding: Bool
    private let approval: DecoderApproval?
    public let privateProtocol: Bool
    public init(executable: URL, model: URL, useGPU: Bool = true, timestampDecoding: Bool = true, approval: DecoderApproval? = nil, privateProtocol: Bool = false) {
        self.executable = executable
        self.model = model
        self.useGPU = useGPU
        self.timestampDecoding = timestampDecoding
        self.approval = approval
        self.privateProtocol = privateProtocol
    }
    public func transcribe(_ audio: [AudioFrame], language: String, vocabulary: [String]) async throws -> SpeechResult {
        let start = Date()
        var arguments = ["-m", model.path, "-f", "-", "-np", "-otxt", "-of", "-", "-l", language.hasPrefix("en") ? "en" : language]
        // The decoder uses timestamp tokens to find speech boundaries. The TXT output omits timestamps.
        if !timestampDecoding { arguments.append("-nt") }
        if !useGPU { arguments.append("-ng") }
        let wav = AudioTools.wav(audio)
        let input: Data
        if privateProtocol {
            arguments.append("--keydown-request-v1")
            input = try SpeechRequest.encode(wav: wav, vocabulary: vocabulary)
        } else { input = wav }
        let output = try await LocalProcess.run(executable: executable, arguments: arguments, input: input, timeout: 60, approval: approval)
        let text: String
        if timestampDecoding {
            text = output.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else {
            text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty, !(privateProtocol && text == "[BLANK_AUDIO]") else { throw MurmurError.empty }
        return SpeechResult(text: text, seconds: Date().timeIntervalSince(start))
    }
}
public struct LegacySystemSpeechProvider: SpeechProvider {
    public let name = "System dictation (on-device)"
    public init() {}
    public func transcribe(_ audio: [AudioFrame], language: String, vocabulary: [String]) async throws -> SpeechResult {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw MurmurError.unavailable("System dictation requires the Speech Recognition permission. The bundled decoder does not need that grant.") }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.supportsOnDeviceRecognition else { throw MurmurError.unavailable("On-device system dictation is unavailable for this language.") }
        let start = Date(); let buffer = try AudioTools.buffer(audio.flatMap(\.samples))
        return try await Deadline.run(seconds: 30) {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false; request.contextualStrings = vocabulary
            let bridge = RecognitionBridge()
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    bridge.install(continuation)
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error { bridge.complete(.failure(error)) }
                        else if let result, result.isFinal { bridge.complete(.success(SpeechResult(text: result.bestTranscription.formattedString, seconds: Date().timeIntervalSince(start)))) }
                    }
                    bridge.setTask(task); request.append(buffer); request.endAudio()
                }
            }, onCancel: { bridge.complete(.failure(CancellationError())) })
        }
    }
}
private final class RecognitionBridge: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<SpeechResult, Error>?
    var task: SFSpeechRecognitionTask?
    var completed = false
    var result: Result<SpeechResult, Error>?
    func install(_ waiting: CheckedContinuation<SpeechResult, Error>) {
        lock.lock(); if let result { lock.unlock(); waiting.resume(with: result) } else { continuation = waiting; lock.unlock() }
    }
    func setTask(_ task: SFSpeechRecognitionTask) { lock.lock(); let stop = completed; if !stop { self.task = task }; lock.unlock(); if stop { task.cancel() } }
    func complete(_ value: Result<SpeechResult, Error>) {
        lock.lock(); guard !completed else { lock.unlock(); return }; completed = true
        result = value; let waiting = continuation; continuation = nil; let task = task; self.task = nil; lock.unlock()
        task?.cancel(); waiting?.resume(with: value)
    }
}

public struct UnavailableSpeechProvider: SpeechProvider {
    public let name = "Unavailable local decoder"
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public func transcribe(_ audio: [AudioFrame], language: String, vocabulary: [String]) async throws -> SpeechResult { throw MurmurError.unavailable(reason) }
}
