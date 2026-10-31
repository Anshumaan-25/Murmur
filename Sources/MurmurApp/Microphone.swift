import AVFoundation
import CoreAudio
import MurmurCore

final class Microphone {
    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false
    private var generation = UUID()
    private var converter: AVAudioConverter?
    var level: ((Float) -> Void)?
    var inputDevice: AudioDeviceID = 0
    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw MurmurError.unavailable("Enable Murmur microphone access in System Settings.") }
        engine = AVAudioEngine()
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
        self.converter = converter; lock.lock(); samples = []; running = true; self.generation = generation; lock.unlock()
        node.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] input, _ in
            guard let self else { return }
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / source.sampleRate + 128)) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }; supplied = true; state.pointee = .haveData; return input
            }
            guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            self.lock.lock(); if self.running && self.generation == generation { self.samples.append(contentsOf: chunk) }; self.lock.unlock()
            self.level?(AudioFrame(chunk).rms)
        }
        engine.prepare()
        do { try engine.start() } catch { engine.inputNode.removeTap(onBus: 0); running = false; throw error }
    }
    func stop() -> [AudioFrame] {
        lock.lock(); let wasRunning = running; running = false; lock.unlock()
        if wasRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        lock.lock(); let result = AudioTools.frames(samples); samples = []; lock.unlock()
        return result
    }
    func cancel() { _ = stop() }
}
