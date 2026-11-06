import AVFoundation
import CoreAudio
import MurmurCore

final class Microphone {
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false
    private var generation = UUID()
    var configurationChanged: (() -> Void)?
    var isCapturing: Bool { engine?.isRunning == true }
    private var levelValue: Float = 0
    private var audioUptime: Double = 0
    private var voiceUptime: Double = 0
    struct Meter { let rms: Float; let lastVoice: Double }
    func meter() -> Meter {
        lock.lock(); defer { lock.unlock() }
        return Meter(rms: ProcessInfo.processInfo.systemUptime - audioUptime < 0.18 ? levelValue : 0, lastVoice: voiceUptime)
    }
    var inputDevice: AudioDeviceID = 0
    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw MurmurError.unavailable("Enable Keydown microphone access in System Settings.") }
        let engine = AVAudioEngine()
        let node = engine.inputNode
        if inputDevice != 0, let unit = node.audioUnit {
            var device = inputDevice
            let code = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard code == noErr else { throw MurmurError.unavailable("The chosen microphone is unavailable.") }
        }
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0 else { throw MurmurError.invalidAudio }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioTools.rate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: source, to: target) else { throw MurmurError.invalidAudio }
        let generation = UUID()
        lock.lock(); samples = []; samples.reserveCapacity(1_920_000); levelValue = 0; voiceUptime = 0; audioUptime = 0; running = true; self.generation = generation; lock.unlock()
        node.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] input, _ in
            guard let self else { return }
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / source.sampleRate + 128)) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }; supplied = true; state.pointee = .haveData; return input
            }
            guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            let rms = AudioFrame(chunk).rms; let now = ProcessInfo.processInfo.systemUptime
            self.lock.lock()
            if self.running && self.generation == generation {
                self.samples.append(contentsOf: chunk); self.levelValue = rms; self.audioUptime = now
                if rms > 0.008 { self.voiceUptime = now }
            }
            self.lock.unlock()
        }
        self.engine = engine
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self, weak engine] _ in
            // Audio-engine teardown must occur outside the engine's notification callback.
            DispatchQueue.main.async { [weak self, weak engine] in
                guard let self, let engine, self.engine === engine, !engine.isRunning else { return }
                self.configurationChanged?()
            }
        }
        engine.prepare()
        do { try engine.start() } catch { cancel(); throw error }
    }

    private func endCapture() -> [Float] {
        lock.lock()
        running = false
        levelValue = 0
        let captured = samples
        samples = []
        lock.unlock()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if let engine {
            self.engine = nil
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        return captured
    }

    func stop() -> [AudioFrame] { AudioTools.frames(endCapture()) }
    func cancel() { _ = endCapture() }
}
