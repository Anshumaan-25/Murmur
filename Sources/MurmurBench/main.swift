import Foundation
import AVFoundation
import Speech
import MurmurCore

if CommandLine.arguments.count < 2 {
    print("Use --file PATH [--decoder PATH --model PATH] or --probe")
} else {
    let args = CommandLine.arguments
    func option(_ key: String) -> String? { guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }; return args[i + 1] }
    let gate = DispatchSemaphore(value: 0)
    Task {
        do {
            if args.contains("--probe") {
                let locales = await SpeechTranscriber.installedLocales
                print("Installed speech languages: \(locales.map(\.identifier).joined(separator: ", "))")
                print("Microphone status: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
            } else if let instruction = option("--rewrite"), let selected = option("--selected"), let decoder = option("--decoder"), let model = option("--model") {
                let start = Date()
                let text = try await CommandRewrite(executable: URL(fileURLWithPath: decoder), model: URL(fileURLWithPath: model)).rewrite(instruction: instruction, selected: selected)
                let json: [String: Any] = ["seconds": Date().timeIntervalSince(start), "text": text]
                print(String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8)!)
            } else if let file = option("--file") {
                let frames = try AudioTools.readFile(URL(fileURLWithPath: file))
                let provider: any SpeechProvider
                if let decoder = option("--decoder"), let model = option("--model") { provider = ExecutableSpeechProvider(executable: URL(fileURLWithPath: decoder), model: URL(fileURLWithPath: model)) } else { provider = SystemSpeechProvider() }
                let result = try await provider.transcribe(frames, language: "en-US", vocabulary: [])
                let json: [String: Any] = ["provider": provider.name, "audio_seconds": Double(frames.flatMap(\.samples).count) / AudioTools.rate, "recognition_seconds": result.seconds, "text": result.text]
                print(String(data: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), encoding: .utf8)!)
            }
        } catch { print("Benchmark unavailable: \(error.localizedDescription)") }
        gate.signal()
    }
    while gate.wait(timeout: .now()) != .success { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
}
