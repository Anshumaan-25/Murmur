import Foundation

public enum WritingStyle: String, Codable, CaseIterable, Sendable { case neutral, formal, casual }
public struct TextContext: Sendable {
    public var application: String
    public var category: ApplicationCategory
    public var preserveCode: Bool
    public var style: WritingStyle
    public var dictionary: [String]
    public var expansions: [String: String]
    public var selected: String
    public var surrounding: String
    public init(application: String = "", category: ApplicationCategory? = nil, preserveCode: Bool = true, style: WritingStyle = .neutral, dictionary: [String] = [], expansions: [String: String] = [:], selected: String = "", surrounding: String = "") {
        self.application = application; self.category = category ?? ApplicationCategory.classify(bundle: application); self.preserveCode = preserveCode; self.style = style; self.dictionary = dictionary; self.expansions = expansions; self.selected = selected; self.surrounding = surrounding
    }
}
public protocol CleanupProvider: Sendable { func clean(_ raw: String, context: TextContext) async throws -> String }
public struct RuleCleanup: CleanupProvider {
    public init() {}
    public func clean(_ raw: String, context: TextContext) async throws -> String { apply(raw, context: context) }
    public func apply(_ raw: String, context: TextContext = TextContext()) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trigger = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if let expansion = context.expansions.first(where: { $0.key.lowercased() == trigger })?.value { return expansion }
        if context.preserveCode && context.category.preservesSyntax {
            for term in context.dictionary where !term.isEmpty { text = replace(text, "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b", NSRegularExpression.escapedTemplate(for: term)) }
            return text
        }
        text = replace(text, #"\b(?:um+|uh+|erm)\b[,\s]*"#, "")
        text = replace(text, #"^so[,\s]+"#, "")
        text = DictationLanguage.numbers(text)
        text = DictationLanguage.corrections(text)
        text = replace(text, #"\b(\w+)(?:\s+\1\b)+"#, "$1")
        for (spoken, written) in [("new paragraph", "\n\n"), ("new line", "\n"), ("question mark", "?"), ("exclamation mark", "!"), ("full stop", "."), ("open parenthesis", "("), ("close parenthesis", ")"), ("comma", ","), ("semicolon", ";")] { text = replace(text, "\\b" + spoken + "\\b", written) }
        if text.range(of: #"^first\b.+\bsecond\b"#, options: [.regularExpression, .caseInsensitive]) != nil && text.range(of: #"\b(?:a|the|my|your)\s+second\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            for (word, number) in [("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("fifth", 5)] {
                text = replace(text, "(?:^|[,;.]?\\s+)" + word + "[,\\s]+", (number == 1 ? "" : "\n") + "\(number). ")
            }
        }
        for term in context.dictionary where !term.isEmpty { text = replace(text, "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b", NSRegularExpression.escapedTemplate(for: term)) }
        if context.style == .formal {
            for (source, target) in [("can't", "cannot"), ("don't", "do not"), ("won't", "will not"), ("I'm", "I am"), ("thanks", "thank you")] { text = replace(text, "\\b" + source + "\\b", target) }
        } else if context.style == .casual { text = replace(text, #"\bregarding\b"#, "about") }
        text = replace(text, #"^you know[,\s]+"#, "")
        text = replace(text, #"^well,\s*"#, "")
        text = replace(text, #"[\t ]+"#, " ")
        text = replace(text, #" +([,.;:!?])"#, "$1")
        text = replace(text, #"([,;:!?])(?=[\p{L}])"#, "$1 ")
        text = replace(text, #" *\n *"#, "\n")
        text = replace(text, #"\bi\b"#, "I")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        guard !text.isEmpty else { return "" }
        var uppercase = true; var output = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if uppercase && character.isLetter { output += String(character).uppercased(); uppercase = false }
            else { output.append(character); if character.isNumber { uppercase = false } }
            if character == "\n" || (".!?".contains(character) && (index + 1 == characters.count || characters[index + 1].isWhitespace)) { uppercase = true }
        }
        if let last = output.last, !".!?:;".contains(last) { output += "." }
        return output
    }
    private func replace(_ text: String, _ expression: String, _ replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

}
public enum TextGuard {
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let left = Array(a.lowercased()); let right = Array(b.lowercased())
        var previous = Array(0...right.count)
        for (i, x) in left.enumerated() {
            var row = [i + 1]
            for (j, y) in right.enumerated() { row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (x == y ? 0 : 1))) }; previous = row
        }
        return previous.last ?? 0
    }
    public static func accepts(_ candidate: String, original: String) -> Bool {
        guard !original.isEmpty, candidate.count <= min(8000, max(30, original.count * 3 / 2)), candidate.count >= original.count / 2 else { return false }
        guard editDistance(candidate, original) <= max(10, original.count * 45 / 100) else { return false }
        let numbers: (String) -> [String] = { $0.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty } }
        return numbers(candidate) == numbers(original)
    }
}
public enum EditingCommand {
    public static func apply(_ instruction: String, selected: String) throws -> String {
        guard !selected.isEmpty else { throw MurmurError.unavailable("Select text before using an editing command.") }
        let command = instruction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let original = instruction.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let expression = try? NSRegularExpression(pattern: #"^(?:please\s+)?replace\s+(.+?)\s+with\s+(.+?)$"#, options: [.caseInsensitive]), let match = expression.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)), let sourceRange = Range(match.range(at: 1), in: original), let targetRange = Range(match.range(at: 2), in: original) {
            let quotes = CharacterSet(charactersIn: "\"“”'")
            var source = String(original[sourceRange]).trimmingCharacters(in: quotes)
            var target = String(original[targetRange]).trimmingCharacters(in: quotes)
            if selected.range(of: source, options: .caseInsensitive) == nil { source = DictationLanguage.numbers(source); target = DictationLanguage.numbers(target) }
            guard !source.isEmpty, selected.range(of: source, options: .caseInsensitive) != nil else { throw MurmurError.unavailable("The selected passage does not contain that text.") }
            return selected.replacingOccurrences(of: source, with: target, options: .caseInsensitive)
        }
        if command.contains("uppercase") || command == "all caps" { return selected.uppercased() }
        if command.contains("lowercase") { return selected.lowercased() }
        if command.contains("shorter") || command.contains("shorten") {
            var text = selected
            for (phrase, replacement) in [("in order to", "to"), ("at this point in time", "now"), ("due to the fact that", "because"), ("I wanted to let you know that ", ""), ("very ", ""), ("really ", "")] { text = text.replacingOccurrences(of: phrase, with: replacement, options: .caseInsensitive) }
            return RuleCleanup().apply(text)
        }
        if command.contains("informal") || command.contains("casual") { return RuleCleanup().apply(selected, context: TextContext(style: .casual)) }
        if command.contains("formal") { return RuleCleanup().apply(selected, context: TextContext(style: .formal)) }
        if command.contains("casual") { return RuleCleanup().apply(selected, context: TextContext(style: .casual)) }
        throw MurmurError.unsupportedCommand
    }
}
