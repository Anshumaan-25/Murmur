import AVFoundation
import CoreAudio
import MurmurCore

/// A session owns its engine, converter and buffers. Engine operations are serialized
/// off the main thread, including teardown before another session opens the device.
@MainActor final class Microphone {
    struct Meter {
        var rms: Float = 0
        var speechSilence: Double = 0
        var heardSpeech = false
        var received = false
        var lastBuffer: Double = 0
        var signal: AudioSignal = .noInput
    }
    struct Capture {
        var frames: [AudioFrame] = []
        var speech: SoundSpeechMonitor?
    }
    private let queue = DispatchQueue(label: "local.murmur.microphone", qos: .userInitiated)
    private var current: MicrophoneTake?
    private var finishing: MicrophoneTake?
    var inputDevice: AudioDeviceID = 0
    var configurationChanged: (() -> Void)?
    var isCapturing: Bool { current != nil }
    func meter() -> Meter { current?.meter() ?? Meter() }
    func markRelease(through cutoff: UInt64) { current?.setCutoff(cutoff) }

    func prime() {
        guard current == nil else { return }
        let take = MicrophoneTake(queue: queue)
        current = take
        let device = inputDevice
        queue.async { [weak self, take] in
            take.open(device: device) { [weak self, weak take] in
                Task { @MainActor in
                    guard let self, let take, self.current === take else { return }
                    self.configurationChanged?()
                }
            }
        }
    }

    func start(maximumSeconds: Double, onReady: @escaping @MainActor () -> Void,
               onLimit: @escaping @MainActor () -> Void, onError: @escaping @MainActor (Error) -> Void) {
        prime()
        guard let take = current else { return }
        queue.async { take.commit(limit: RecordingPolicy.sampleLimit(seconds: maximumSeconds),
                                  onReady: onReady, onLimit: onLimit, onError: onError) }
    }

    func stop(through cutoff: UInt64) -> Task<Capture, Never> {
        guard let take = current else { return Task { Capture() } }
        current = nil
        finishing = take
        take.setCutoff(cutoff)
        return Task {
            let capture = await withCheckedContinuation { continuation in
                queue.async { take.finish { continuation.resume(returning: $0) } }
            }
            if finishing === take { finishing = nil }
            return capture
        }
    }

    func cancel() {
        for take in [current, finishing].compactMap({ $0 }) {
            take.markCancelled()
            queue.async { take.close() }
        }
        current = nil
        finishing = nil
    }
}

/// Fixed native-format slots. The tap only copies bytes into preallocated memory
/// and signals the consumer. Unconfirmed audio never enters the classifier.
final class TapBufferRing {
    private let lock = NSLock()
    private let buffers: [AVAudioPCMBuffer]
    private var times: [UInt64]
    private var read = 0, count = 0
    private var committed = false
    private var lost = false
    var lostAudio: Bool { lock.withLock { lost } }

    init(format: AVAudioFormat, capacity: AVAudioFrameCount, slots: Int) throws {
        buffers = try (0..<slots).map { _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw MurmurError.invalidAudio }
            return buffer
        }
        times = Array(repeating: 0, count: slots)
    }

    func commit() { lock.withLock { committed = true } }

    func push(_ input: AVAudioPCMBuffer, hostTime: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard input.format == buffers[0].format else { lost = true; return }
        let stride = Int(input.format.streamDescription.pointee.mBytesPerFrame)
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
        var offset: AVAudioFrameCount = 0
        while offset < input.frameLength {
            if count == buffers.count {
                lost = true
                guard !committed else { return } // consumer may be using the oldest slot
                read = (read + 1) % buffers.count
                count -= 1
            }
            let slot = (read + count) % buffers.count
            let output = buffers[slot]
            let frames = min(output.frameCapacity, input.frameLength - offset)
            output.frameLength = frames
            let dst = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
            let byteOffset = Int(offset) * stride, bytes = Int(frames) * stride
            for index in src.indices {
                guard let from = src[index].mData, let to = dst[index].mData,
                      byteOffset + bytes <= Int(src[index].mDataByteSize) else { lost = true; return }
                memcpy(to, from.advanced(by: byteOffset), bytes)
            }
            times[slot] = hostTime == 0 ? 0 : hostTime + AVAudioTime.hostTime(forSeconds: Double(offset) / input.format.sampleRate)
            count += 1
            offset += frames
        }
    }

    func drain(_ consume: (AVAudioPCMBuffer, UInt64) -> Void) {
        while let index = lock.withLock({ committed && count > 0 ? read : nil }) {
            let stamp = lock.withLock { times[index] }
            consume(buffers[index], stamp)
            lock.withLock { read = (read + 1) % buffers.count; count -= 1 }
        }
    }
}

final class MicrophoneTake: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var cancelled = false
    private var cutoff: UInt64?
    private var reading = Microphone.Meter()
    private var meterMonitor: SoundSpeechMonitor?
    // Remaining state belongs to queue.
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private var signal: DispatchSourceUserDataAdd?
    private var ring: TapBufferRing?
    private var converter: AVAudioConverter?
    private var output: AVAudioPCMBuffer?
    private var monitor: SoundSpeechMonitor?
    private var samples: [Float] = []
    private var limit = 0
    private var lastInputEnd: UInt64 = 0
    // Usually one continuous interval. A device gap starts another interval.
    // This lets a late main-loop key-up trim PCM already delivered by the tap.
    private struct Interval { let start: UInt64; var frames: Int }
    private var intervals: [Interval] = []
    private var error: Error?
    private var closed = false
    private var ready: (@MainActor () -> Void)?
    private var limitReached: (@MainActor () -> Void)?
    private var completion: ((Microphone.Capture) -> Void)?
    init(queue: DispatchQueue) { self.queue = queue }
    func markCancelled() { lock.withLock { cancelled = true } }
    func setCutoff(_ time: UInt64) { lock.withLock { cutoff = time } }
    func meter() -> Microphone.Meter {
        var (snapshot, classifier) = lock.withLock { (reading, meterMonitor) }
        if let evidence = classifier?.snapshot() {
            snapshot.heardSpeech = evidence.heardSpeech
            snapshot.speechSilence = evidence.silence
        }
        if ProcessInfo.processInfo.systemUptime - snapshot.lastBuffer >= 0.18 { snapshot.rms = 0 }
        return snapshot
    }

    func open(device: AudioDeviceID, changed: @escaping () -> Void) {
        guard !lock.withLock({ cancelled }) else { return }
        do {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                throw MurmurError.unavailable("Enable Keydown microphone access in System Settings.")
            }
            let engine = AVAudioEngine()
            let node = engine.inputNode
            if device != 0, let unit = node.audioUnit {
                var choice = device
                guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                           0, &choice, UInt32(MemoryLayout.size(ofValue: choice))) == noErr else {
                    throw MurmurError.unavailable("The chosen microphone is unavailable.")
                }
            }
            let source = node.outputFormat(forBus: 0)
            let tap = try prepareTap(format: source)
            node.installTap(onBus: 0, bufferSize: 1024, format: source, block: tap)
            self.engine = engine
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, !self.closed, let engine = self.engine,
                          !engine.isRunning || engine.inputNode.outputFormat(forBus: 0) != source else { return }
                    changed()
                }
            }
            if !lock.withLock({ cancelled }) { try engine.start() }
        } catch { self.error = error }
    }

    func prepareTap(format: AVAudioFormat) throws -> AVAudioNodeTapBlock {
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioTools.rate, channels: 1, interleaved: false),
              let conversion = AVAudioConverter(from: format, to: target),
              let scratch = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else { throw MurmurError.invalidAudio }
        let slots = max(8, Int(ceil(format.sampleRate / 1024)))
        let ring = try TapBufferRing(format: format, capacity: 1024, slots: slots)
        let signal = DispatchSource.makeUserDataAddSource(queue: queue)
        self.converter = conversion; self.output = scratch; self.ring = ring; self.signal = signal
        signal.setEventHandler { [weak self] in self?.consumePending() }
        signal.resume()
        return { input, time in
            ring.push(input, hostTime: time.isHostTimeValid ? time.hostTime : 0)
            signal.add(data: 1)
        }
    }

    func commit(limit: Int, onReady: @escaping @MainActor () -> Void, onLimit: @escaping @MainActor () -> Void,
                onError: @escaping @MainActor (Error) -> Void) {
        guard !closed, !lock.withLock({ cancelled }) else { return }
        if let error { Task { @MainActor in onError(error) }; return }
        self.limit = limit; ready = onReady; limitReached = onLimit
        monitor = SoundSpeechMonitor()
        lock.withLock { meterMonitor = monitor }
        ring?.commit()
        consumePending()
    }

    private func consumePending() {
        ring?.drain { input, start in
            let length = input.frameLength
            let rate = input.format.sampleRate
            let end = start + AVAudioTime.hostTime(forSeconds: Double(length) / rate)
            let stop = lock.withLock { cutoff }
            if let stop {
                if start == 0 || start >= stop { input.frameLength = 0 }
                else if end > stop {
                    input.frameLength = min(length, AVAudioFrameCount(AVAudioTime.seconds(forHostTime: stop - start) * rate))
                }
            }
            if input.frameLength > 0 {
                if start > 0 {
                    if let last = intervals.last,
                       abs(AVAudioTime.seconds(forHostTime: start) - AVAudioTime.seconds(forHostTime: last.start)
                           - Double(last.frames) / rate) < 0.5 / rate {
                        intervals[intervals.count - 1].frames += Int(input.frameLength)
                    } else {
                        intervals.append(Interval(start: start, frames: Int(input.frameLength)))
                    }
                }
                convert(input)
            }
            lastInputEnd = max(lastInputEnd, end)
        }
        if completion != nil, let stop = lock.withLock({ cutoff }), lastInputEnd >= stop { close() }
    }

    private func convert(_ input: AVAudioPCMBuffer?) {
        guard let converter, let output, samples.count < limit else { return }
        var supplied = false
        while samples.count < limit {
            output.frameLength = 0
            var failure: NSError?
            let status = converter.convert(to: output, error: &failure) { _, state in
                if let input, !supplied { supplied = true; state.pointee = .haveData; return input }
                state.pointee = input == nil ? .endOfStream : .noDataNow
                return nil
            }
            if status == .error { error = failure ?? MurmurError.invalidAudio; return }
            let count = min(Int(output.frameLength), limit - samples.count)
            if count > 0, let channel = output.floatChannelData?[0] {
                let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
                guard chunk.allSatisfy({ $0.isFinite }) else { error = MurmurError.invalidAudio; return }
                samples.append(contentsOf: chunk)
                monitor?.append(chunk)
                let rms = AudioFrame(chunk).rms
                let peak = chunk.reduce(Float.zero) { max($0, abs($1)) }
                lock.withLock {
                    reading.received = true; reading.rms = rms
                    reading.lastBuffer = ProcessInfo.processInfo.systemUptime
                    reading.signal = AudioSignal.classify(rms: rms, peak: peak, received: true)
                }
                if let ready { self.ready = nil; Task { @MainActor in ready() } }
            }
            if status != .haveData || count == 0 { break }
        }
        if samples.count == limit, let limitReached {
            self.limitReached = nil
            Task { @MainActor in limitReached() }
        }
    }

    func finish(_ completion: @escaping (Microphone.Capture) -> Void) {
        guard !closed else { completion(.init()); return }
        self.completion = completion
        consumePending()
        guard !closed else { return }
        // Give the hardware its in-flight tap, bounded even on a disconnected
        // route. Input host timestamps exclude samples acquired after release.
        guard error == nil, engine?.isRunning == true else { close(); return }
        queue.asyncAfter(deadline: .now() + .milliseconds(160)) { [weak self] in self?.close() }
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        signal?.cancel()
        let done = completion
        completion = nil
        if let done, !lock.withLock({ cancelled }) {
            consumePending()
            convert(nil) // end-of-stream drains resampler latency
            let clipped = trimLateRelease()
            let complete = !clipped && error == nil && ring?.lostAudio == false
            if !complete { monitor?.cancel() }
            done(.init(frames: AudioTools.frames(samples), speech: complete ? monitor : nil))
        } else {
            monitor?.cancel()
            done?(.init())
        }
        samples = []; ring = nil; converter = nil; output = nil; engine = nil
    }

    private func trimLateRelease() -> Bool {
        guard let stop = lock.withLock({ cutoff }), let rate = converter?.inputFormat.sampleRate,
              let last = intervals.last else { return false }
        let end = last.start + AVAudioTime.hostTime(forSeconds: Double(last.frames) / rate)
        guard end > stop + AVAudioTime.hostTime(forSeconds: 1 / rate) else { return false }
        var frames = 0
        for interval in intervals where interval.start < stop {
            let available = AVAudioTime.seconds(forHostTime: stop - interval.start) * rate
            frames += min(interval.frames, Int(available.rounded()))
        }
        let keep = min(samples.count, Int((Double(frames) * AudioTools.rate / rate).rounded()))
        samples.removeLast(samples.count - keep)
        // The live classifier could have seen the excluded audio.
        return true
    }
}
