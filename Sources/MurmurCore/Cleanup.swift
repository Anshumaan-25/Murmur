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
    public var mode: DictationMode
    public init(application: String = "", category: ApplicationCategory? = nil, preserveCode: Bool = true, style: WritingStyle = .neutral, dictionary: [String] = [], expansions: [String: String] = [:], selected: String = "", surrounding: String = "", mode: DictationMode = .automatic) {
        self.application = application; self.category = category ?? ApplicationCategory.classify(bundle: application); self.preserveCode = preserveCode; self.style = style; self.dictionary = dictionary; self.expansions = expansions; self.selected = selected; self.surrounding = surrounding
        self.mode = mode
    }
}
public protocol CleanupProvider: Sendable { func clean(_ raw: String, context: TextContext) async throws -> String }
public struct RuleCleanup: CleanupProvider {
    public init() {}
    public func clean(_ raw: String, context: TextContext) async throws -> String { apply(raw, context: context) }
    public func apply(_ raw: String, context: TextContext = TextContext()) -> String {
        if context.mode == .exact { return SpellingCommand.apply(raw) }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trigger = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if let expansion = context.expansions.first(where: { $0.key.lowercased() == trigger })?.value { return expansion }
        if context.mode == .automatic && context.preserveCode && context.category.preservesSyntax { return raw }
        var protected = ProtectedSpans()
        text = protected.mask(text)
        for term in context.dictionary where !term.isEmpty { text = replace(text, "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b", NSRegularExpression.escapedTemplate(for: term)) }
        text = protected.maskTerms(text, terms: context.dictionary)
        text = { segment in
            var prose = replace(segment, #"\b(?:um+|uh+|erm)\b[,\s]*"#, "")
            prose = DictationLanguage.corrections(DictationLanguage.numbers(prose))
            for (spoken, written) in [("new paragraph", "\n\n"), ("new line", "\n"), ("question mark", "?"), ("exclamation mark", "!"), ("full stop", "."), ("open parenthesis", "("), ("close parenthesis", ")"), ("comma", ","), ("semicolon", ";")] {
                let literal = #"(^|\b(?:a|an|the|word|literal|type|say)\s+)"# + spoken + #"\b|\b"# + spoken + #"\b(\s+(?:key|character|word|symbol|button|of)\b)|\b("# + spoken + #")\b"#
                guard let regex = try? NSRegularExpression(pattern: literal, options: .caseInsensitive) else { continue }
                for match in regex.matches(in: prose, range: NSRange(prose.startIndex..., in: prose)).reversed() {
                    if let range = Range(match.range(at: 3), in: prose) { prose.replaceSubrange(range, with: written) }
                }
            }
            return prose
        }(text)
        if raw.range(of: #"^\s*(?:um+|uh+|erm)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            text = replace(text, #"^so[,\s]+"#, "")
        }
        text = replace(text, #"^((?:we|i|you|they|the))(?:(?:[ \t]+)\1\b)+"#, "$1")
        if text.range(of: #"^first\b.+\bsecond\b"#, options: [.regularExpression, .caseInsensitive]) != nil && text.range(of: #"\b(?:a|the|my|your)\s+second\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            for (word, number) in [("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("fifth", 5)] {
                text = replace(text, "(?:^|[,;.]?\\s+)" + word + "[,\\s]+", (number == 1 ? "" : "\n") + "\(number). ")
            }
        }
        if context.style == .formal {
            for (source, target) in [("can't", "cannot"), ("don't", "do not"), ("won't", "will not"), ("I'm", "I am"), ("thanks", "thank you")] { text = replace(text, "\\b" + source + "\\b", target) }
        } else if context.style == .casual { text = replace(text, #"\bregarding\b"#, "about") }
        text = protected.maskStructured(text)
        text = replace(text, #"(?<=[%.!?])(?=[A-Z][a-z])"#, " ", insensitive: false)
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
        output = protected.restore(output)
        let ending = output.reversed().drop(while: { "\"”’»".contains($0) }).first
        if let ending, !".!?:;".contains(ending) { output += "." }
        return output
    }
    private func replace(_ text: String, _ expression: String, _ replacement: String, insensitive: Bool = true) -> String {
        guard let regex = try? NSRegularExpression(pattern: expression, options: insensitive ? [.caseInsensitive] : []) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

}
public enum EditingCommand {
    public static func apply(_ instruction: String, selected: String) throws -> String {
        guard !selected.isEmpty else { throw MurmurError.unavailable("Select text before using an editing command.") }
        let original = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        var command = original.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        if command.hasPrefix("please ") { command.removeFirst("please ".count) }
        let operand = #"(?:"[^"]+"|“[^”]+”|[^\s"“”]+)"#
        if let regex = try? NSRegularExpression(pattern: #"^(?:please\s+)?replace\s+("# + operand + #")\s+with\s+("# + operand + #")(?:\.(?<=”\.|"\.))?$"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
           let a = Range(match.range(at: 1), in: original), let b = Range(match.range(at: 2), in: original) {
            func quoted(_ operand: Substring) -> Bool { operand.first == "\"" || operand.first == "“" }
            func unquote(_ operand: Substring) -> String {
                quoted(operand) ? String(operand.dropFirst().dropLast()) : String(operand)
            }
            var source = unquote(original[a])
            var target = unquote(original[b])
            func occurrences(_ term: String) -> [NSTextCheckingResult] {
                guard let pattern = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_@-])(?<!\d[.,:/])"# + NSRegularExpression.escapedPattern(for: term) + #"(?![\p{L}\p{N}_@-]|[.,:/]\d)"#) else { return [] }
                return pattern.matches(in: selected, range: NSRange(selected.startIndex..., in: selected))
            }
            var matches = occurrences(source)
            if matches.isEmpty && !quoted(original[a]) {
                source = DictationLanguage.numbers(source)
                if !quoted(original[b]) { target = DictationLanguage.numbers(target) }
                matches = occurrences(source)
            }
            guard !matches.isEmpty else { throw MurmurError.unavailable("The selected passage does not contain that exact text.") }
            var text = selected
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: target) }
            }
            return text
        }

        switch command {
        case "uppercase", "all caps", "make this uppercase", "make it uppercase": return selected.uppercased()
        case "lowercase", "make this lowercase", "make it lowercase": return selected.lowercased()
        case "shorten", "shorten this", "make this shorter", "make it shorter":
            var result = replace(selected, #"^I wanted to let you know that ([a-z])"#) { $0[1].uppercased() }
            for (phrase, replacement) in [("in order to", "to"), ("at this point in time", "now"), ("due to the fact that", "because"), ("really ", "")] {
                result = replace(result, "\\b" + phrase + (phrase.hasSuffix(" ") ? "" : "\\b")) { _ in replacement }
            }
            return result
        case "formal", "make formal", "make it formal", "make this formal":
            var result = selected
            for (source, target) in [("can't", "cannot"), ("don't", "do not"), ("won't", "will not"), ("I'm", "I am"), ("thanks", "thank you")] {
                result = replace(result, "\\b" + source + "\\b") { match in
                    match[0].first?.isUppercase == true ? target.prefix(1).uppercased() + target.dropFirst() : target
                }
            }
            return result
        case "informal", "casual", "make informal", "make casual", "make it informal", "make it casual", "make this informal", "make this casual":
            return replace(selected, #"\bregarding\b"#) { $0[0].first?.isUppercase == true ? "About" : "about" }
        default: throw MurmurError.unsupportedCommand
        }
    }

    private static func replace(_ text: String, _ pattern: String, using replacement: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let groups = (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement(groups)) }
        }
        return result
    }
}
