import Foundation

public enum DictationMode: String, Codable, CaseIterable, Sendable {
    case automatic, dictate, exact
    public var title: String {
        switch self { case .automatic: return "Follow app preference"; case .dictate: return "Dictate prose"; case .exact: return "Exact text" }
    }
}

enum SpellingCommand {
    static func apply(_ raw: String) -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.last == "." { normalized.removeLast() }
        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.first?.lowercased() == "spell", words.count > 1, words.count <= 256 else { return raw }
        if words.count == 2, words[1].range(of: #"^(?:[A-Za-z]+[-_][A-Za-z0-9_-]*[0-9][A-Za-z0-9_-]*|[0-9]+(?:\.[0-9]+)+)$"#, options: .regularExpression) != nil { return words[1] }
        let symbols = ["hyphen":"-", "dash":"-", "dot":".", "period":".", "underscore":"_", "space":" ", "at":"@", "slash":"/", "colon":":", "plus":"+", "zero":"0", "oh":"0"]
        var output = ""
        for word in words.dropFirst() {
            let key = word.lowercased()
            if let symbol = symbols[key] { output += symbol }
            else if key.count == 1, key.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.decimalDigits).contains($0) }), key.utf8.count == 1 { output += key.uppercased() }
            else {
                let number = key == "one" ? "1" : DictationLanguage.numbers(key)
                guard number != key, let value = Int(number), (0...99).contains(value) else { return raw }
                output += number
            }
        }
        return output
    }
}
