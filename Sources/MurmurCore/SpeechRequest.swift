import Foundation

public enum SpeechRequest {
    public static let version = 1
    public static let maximumAudioBytes = 19_200_044 // 600 seconds of mono PCM16 WAV.
    public static func vocabulary(_ terms: [String], near caret: CaretContext?) -> [String] {
        // The dictionary editor presents terms alphabetically. Preserve stable
        // order within each group, but retain distinctive spellings first.
        var distinctive: [String] = [], ordinary: [String] = []
        for term in terms {
            if term.contains(where: { $0.isUppercase || $0.isNumber || "_-.+#".contains($0) }) {
                distinctive.append(term)
            } else {
                ordinary.append(term)
            }
        }
        let dictionary = distinctive + ordinary
        guard let caret else { return vocabulary(dictionary) }
        func isTermCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || "_-.+#".contains(c) }
        func tokens(_ text: String) -> [String] {
            text.split(whereSeparator: { !isTermCharacter($0) })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".-")) }
                .filter { $0.contains(where: \.isLetter) && $0.count > 1 && !stopWords.contains($0.lowercased()) }
        }
        var nearby: [String] = []
        var prefix = caret.prefix[...], suffix = caret.suffix[...]
        if caret.selected.isEmpty, let before = prefix.last, let after = suffix.first,
           isTermCharacter(before), isTermCharacter(after) {
            let leftPart = prefix.reversed().prefix(while: isTermCharacter).count
            let rightPart = suffix.prefix(while: isTermCharacter).count
            nearby = tokens(String(prefix.suffix(leftPart)) + String(suffix.prefix(rightPart)))
            prefix = prefix.dropLast(leftPart)
            suffix = suffix.dropFirst(rightPart)
        }
        let left = Array(tokens(String(prefix)).reversed()), right = tokens(String(suffix))
        for i in 0..<max(left.count, right.count) {
            if i < left.count { nearby.append(left[i]) }
            if i < right.count { nearby.append(right[i]) }
        }
        nearby.append(contentsOf: tokens(caret.selected))
        // Reserve early positions for both sources even with a full dictionary.
        // User spellings win when a nearby token matches a configured entry.
        var spellings: [String: String] = [:]
        for term in dictionary { spellings[term.lowercased()] = term }
        nearby = nearby.map { spellings[$0.lowercased()] ?? $0 }
        return vocabulary(Array(dictionary.prefix(1)) + nearby.prefix(8) + dictionary.dropFirst() + nearby.dropFirst(8))
    }
    private static let stopWords = Set("an the as at and are but by for from in into is it of on or that this to was with".components(separatedBy: " "))
    public static func vocabulary(_ terms: [String]) -> [String] {
        var result: [String] = [], bytes = 0, seen = Set<String>()
        for term in terms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.utf8.count <= 160,
                  !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(clean.lowercased()).inserted else { continue }
            if result.count == 64 { break }
            let cost = clean.utf8.count + (result.isEmpty ? 0 : 2)
            guard bytes + cost <= 1024 else { continue }
            result.append(clean); bytes += cost
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
