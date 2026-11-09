import Foundation

public enum SpeechRequest {
    public static let version = 1
    public static let maximumAudioBytes = 19_200_044 // 600 seconds of mono PCM16 WAV.
    public static func vocabulary(_ terms: [String]) -> [String] {
        var result: [String] = [], bytes = 0, seen = Set<String>()
        for term in terms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.utf8.count <= 160,
                  !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(clean.lowercased()).inserted else { continue }
            guard bytes + clean.utf8.count + 2 <= 1024, result.count < 64 else { break }
            result.append(clean); bytes += clean.utf8.count + 2
        }
        return result
    }
    public static func encode(wav: Data, vocabulary terms: [String]) throws -> Data {
        guard !wav.isEmpty, wav.count <= maximumAudioBytes else { throw MurmurError.invalidAudio }
        let prompt = Data(vocabulary(terms).joined(separator: ", ").utf8)
        var data = Data("KDSP".utf8)
        for value in [UInt32(version), UInt32(prompt.count), UInt32(wav.count)] {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(prompt); data.append(wav)
        return data
    }
}
