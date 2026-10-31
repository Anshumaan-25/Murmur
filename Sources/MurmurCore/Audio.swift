import Foundation
import AVFoundation

public struct AudioFrame: Sendable {
    public let samples: [Float]
    public init(_ samples: [Float]) { self.samples = samples }
    public var rms: Float { samples.isEmpty ? 0 : sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)) }
}
public enum AudioTools {
    public static let rate = 16_000.0
    public static let frameCount = 640
    public static func frames(_ samples: [Float]) -> [AudioFrame] {
        stride(from: 0, to: samples.count, by: frameCount).map { AudioFrame(Array(samples[$0..<min(samples.count, $0 + frameCount)])) }
    }
    public static func trimmed(_ frames: [AudioFrame], threshold: Float = 0.008, padding: Int = 5) -> [AudioFrame] {
        guard let first = frames.firstIndex(where: { $0.rms > threshold }), let last = frames.lastIndex(where: { $0.rms > threshold }) else { return [] }
        return Array(frames[max(0, first - padding)...min(frames.count - 1, last + padding)])
    }
    public static func buffer(_ samples: [Float], format: AVAudioFormat? = nil) throws -> AVAudioPCMBuffer {
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        guard !samples.isEmpty, let input = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(samples.count)) else { throw MurmurError.invalidAudio }
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { source in input.floatChannelData![0].update(from: source.baseAddress!, count: samples.count) }
        return try format.map { try convert(input, to: $0) } ?? input
    }
    public static func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if input.format == format { return input }
        guard let converter = AVAudioConverter(from: input.format, to: format), let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate) + 256)) else { throw MurmurError.invalidAudio }
        var supplied = false; var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let error { throw error }; guard status != .error else { throw MurmurError.invalidAudio }; return output
    }
    public static func readFile(_ url: URL) throws -> [AudioFrame] {
        let file = try AVAudioFile(forReading: url)
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw MurmurError.invalidAudio }
        try file.read(into: input)
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let converted = try convert(input, to: mono)
        return frames(Array(UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength))))
    }
    public static func wav(_ frames: [AudioFrame]) -> Data {
        let samples = frames.flatMap(\.samples)
        var data = Data(); func u16(_ n: UInt16) { var v = n.littleEndian; data.append(Data(bytes: &v, count: 2)) }; func u32(_ n: UInt32) { var v = n.littleEndian; data.append(Data(bytes: &v, count: 4)) }
        data.append(Data("RIFF".utf8)); u32(UInt32(36 + samples.count * 2)); data.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16); data.append(Data("data".utf8)); u32(UInt32(samples.count * 2))
        for sample in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32767))) }; return data
    }
}
