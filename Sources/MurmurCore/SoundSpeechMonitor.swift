import Foundation
import AVFoundation
import SoundAnalysis

/// Local, in-memory analysis. Bounded buffering keeps a slow classifier from
/// retaining an unlimited audio queue. Failure always leaves results review-only.
public final class SoundSpeechMonitor: NSObject, SNResultsObserving, @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.murmur.speech-evidence", qos: .userInitiated)
    private let lock = NSLock()
    private var evidence = SpeechEvidence()
    private var pending = 0
    private var ended = false
    private var analyzer: SNAudioStreamAnalyzer?
    private var position: AVAudioFramePosition = 0
    public override init() {
        super.init()
        queue.async {
            do {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                guard request.knownClassifications.contains("speech") else { throw MurmurError.invalidAudio }
                request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 16_000)
                request.overlapFactor = 0.5
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioTools.rate, channels: 1, interleaved: false)!
                let analyzer = SNAudioStreamAnalyzer(format: format)
                try analyzer.add(request, withObserver: self)
                self.analyzer = analyzer
            } catch { self.invalidate() }
        }
    }
    public func snapshot() -> SpeechEvidence { lock.lock(); defer { lock.unlock() }; return evidence }
    /// The same classifier for imported synthetic fixtures, with backpressure.
    public static func assess(_ frames: [AudioFrame]) async -> SpeechEvidence {
        let monitor = SoundSpeechMonitor()
        defer { monitor.cancel() }
        for frame in frames {
            if Task.isCancelled { monitor.cancel(); return monitor.snapshot() }
            monitor.append(frame.samples)
            await withCheckedContinuation { continuation in monitor.queue.async { continuation.resume() } }
        }
        return await monitor.finish()
    }
    private func invalidate() { lock.lock(); evidence.fail(); lock.unlock() }
    public func append(_ samples: [Float]) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }), pending + samples.count <= 32_000 else {
            evidence.fail(); ended = true; lock.unlock(); return
        }
        pending += samples.count
        lock.unlock()
        queue.async {
            defer { self.lock.lock(); self.pending -= samples.count; self.lock.unlock() }
            do {
                let buffer = try AudioTools.buffer(samples)
                self.analyzer?.analyze(buffer, atAudioFramePosition: self.position)
                self.position += AVAudioFramePosition(samples.count)
            } catch { self.invalidate() }
        }
    }
    public func finish() async -> SpeechEvidence {
        await withCheckedContinuation { continuation in
            lock.lock(); ended = true; lock.unlock()
            queue.async {
                self.analyzer?.completeAnalysis()
                continuation.resume(returning: self.snapshot())
                self.analyzer?.removeAllRequests(); self.analyzer = nil
            }
        }
    }
    public func cancel() {
        lock.lock(); evidence.fail(); ended = true; lock.unlock()
        queue.async { self.analyzer?.removeAllRequests(); self.analyzer = nil }
    }
    public func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { invalidate(); return }
        lock.lock()
        evidence.observe(start: result.timeRange.start.seconds, end: CMTimeRangeGetEnd(result.timeRange).seconds,
                         confidence: result.classification(forIdentifier: "speech")?.confidence ?? 0)
        lock.unlock()
    }
    public func request(_ request: SNRequest, didFailWithError error: Error) { invalidate() }
    public func requestDidComplete(_ request: SNRequest) { lock.lock(); evidence.complete(); lock.unlock() }
}
