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
    public var caret: CaretContext?
    public var mode: DictationMode
    var isCodex: Bool { application.lowercased() == "com.openai.codex" }
    func usesTechnicalFormatting(_ raw: String) -> Bool {
        guard mode == .automatic, preserveCode, category.preservesSyntax else { return false }
        return !isCodex || !DictationFormatting.isComposerProse(raw)
    }
    public init(application: String = "", category: ApplicationCategory? = nil, preserveCode: Bool = true, style: WritingStyle = .neutral, dictionary: [String] = [], expansions: [String: String] = [:], selected: String = "", surrounding: String = "", mode: DictationMode = .automatic, caret: CaretContext? = nil) {
        self.application = application; self.category = category ?? ApplicationCategory.classify(bundle: application); self.preserveCode = preserveCode; self.style = style; self.dictionary = dictionary; self.expansions = expansions; self.selected = selected; self.surrounding = surrounding
        self.mode = mode
        self.caret = caret
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
        if context.usesTechnicalFormatting(raw) {
            return DictationFormatting.technical(raw, dictionary: context.dictionary)
        }
        var protected = ProtectedSpans()
        text = protected.mask(text)
        for term in context.dictionary where !term.isEmpty { text = replace(text, "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b", NSRegularExpression.escapedTemplate(for: term)) }
        text = protected.maskTerms(text, terms: context.dictionary)
        if context.isCodex { text = DictationFormatting.retrievalTerminology(text) }
        var spokenFinalStop = false
        text = { segment in
            var prose = replace(segment, #"\b(?:um+|uh+|erm)\b[,\s]*"#, "")
            prose = DictationFormatting.repairs(prose)
            prose = DictationFormatting.notation(prose, acronyms: true)
            prose = protected.mask(prose)
            prose = DictationLanguage.corrections(DictationLanguage.numbers(prose))
            if context.caret != nil {
                if prose.range(of: #"^period\.?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    spokenFinalStop = true
                    return "."
                }
                prose = replace(prose, #"\binsert (?:a )?period\.?$"#, "full stop")
            }
            for (spoken, written) in [("new paragraph", "\n\n"), ("new line", "\n"), ("question mark", "?"), ("exclamation mark", "!"), ("full stop", "."), ("open parenthesis", "("), ("close parenthesis", ")"), ("comma", ","), ("semicolon", ";")] {
                let literal = #"(^|\b(?:a|an|the|word|literal|type|say)\s+)"# + spoken + #"\b|\b"# + spoken + #"\b(\s+(?:key|character|word|symbol|button|of)\b)|\b("# + spoken + #")\b"#
                guard let regex = try? NSRegularExpression(pattern: literal, options: .caseInsensitive) else { continue }
                for match in regex.matches(in: prose, range: NSRange(prose.startIndex..., in: prose)).reversed() {
                    if let range = Range(match.range(at: 3), in: prose) {
                        if written == ".", prose[range.upperBound...].allSatisfy({ $0 == "." || $0.isWhitespace }) {
                            spokenFinalStop = true
                            prose.removeSubrange(range.upperBound...)
                        }
                        prose.replaceSubrange(range, with: written)
                    }
                }
            }
            return prose
        }(text)
        if raw.range(of: #"^\s*(?:um+|uh+|erm)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            text = replace(text, #"^so[,\s]+"#, "")
        }
        text = DictationFormatting.prosePunctuation(text)
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
        let startsSentence = context.caret?.startsSentence ?? true
        let fragment = !startsSentence || context.caret?.continuesOnRight == true
        if fragment && !spokenFinalStop && text.hasSuffix(".") && !text.hasSuffix("..") { text.removeLast() }
        // Whisper capitalizes the start of a take. Preserve dictionary and
        // structured spans (already masked), acronyms, I, and nearby spellings.
        if !startsSentence, let caret = context.caret, let first = text.first, first.isUppercase {
            let token = text.prefix(while: { $0.isLetter })
            let neighbors = [caret.prefix, caret.selected, caret.suffix]
            let alreadyCapitalized = neighbors.contains { $0.split(whereSeparator: { !$0.isLetter }).contains(token) }
            if token != "I", token.dropFirst().allSatisfy({ $0.isLowercase }), !alreadyCapitalized {
                text.replaceSubrange(text.startIndex...text.startIndex, with: first.lowercased())
            }
        }
        var uppercase = startsSentence; var output = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if uppercase && character.isLetter { output += String(character).uppercased(); uppercase = false }
            else { output.append(character); if character.isNumber { uppercase = false } }
            if character == "\n" || (".!?".contains(character) && (index + 1 == characters.count || characters[index + 1].isWhitespace)) { uppercase = true }
        }
        output = protected.restore(output)
        let ending = output.reversed().drop(while: { "\"”’»".contains($0) }).first
        if !fragment, !spokenFinalStop, DictationFormatting.isQuestion(output),
           ending == output.last, ending == "." || ending?.isLetter == true || ending?.isNumber == true {
            if output.hasSuffix(".") { output.removeLast() }
            output += "?"
        } else if !fragment, let ending, !".!?:;".contains(ending) { output += "." }
        return context.caret?.join(output) ?? output
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
        case "title case", "make it title case", "make this title case", "capitalize this", "capitalize each word":
            return replace(selected, #"\S*(?:://|@)\S*|"# + CodeIdentifier.wordPattern + #"(?:['’]"# + CodeIdentifier.wordPattern + #")*"#) { match in
                let word = match[0]
                guard !word.contains("://"), !word.contains("@"), !CodeIdentifier.looksLikeIdentifier(word[...]),
                      let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
        case "bullet list", "make it a bullet list", "make this a bullet list", "bullet points":
            return try list(selected, numbered: false)
        case "numbered list", "make it a numbered list", "make this a numbered list", "number this list":
            return try list(selected, numbered: true)
        case "trim whitespace", "trim the whitespace":
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MurmurError.empty }
            return trimmed
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

    private static func list(_ text: String, numbered: Bool) throws -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let entries = lines.filter { !$0.isEmpty }
        guard !entries.isEmpty else { throw MurmurError.empty }

        // Only remove number prefixes when the selected lines form an existing list.
        let alreadyNumbered = entries.enumerated().allSatisfy { index, entry in
            entry.range(of: #"^\#(index + 1)[.)][ \t]+\S"#, options: .regularExpression) != nil
        }
        let marker = alreadyNumbered ? #"^\d+[.)][ \t]+"# : #"^[-*•][ \t]+"#
        var number = 0
        return lines.map { line in
            guard !line.isEmpty else { return "" }
            let entry = line.replacingOccurrences(of: marker, with: "", options: .regularExpression)
            number += 1
            return (numbered ? "\(number). " : "- ") + entry
        }.joined(separator: "\n")
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
