import Foundation

/// Spoken notation is recognized only in delimited filename/path expressions.
/// Other symbols, including literal shell syntax, pass through unchanged.
enum DictationFormatting {
    private static let filename = #"(?<![\w./-])(?!(?:a|the|extension|suffix|with|an|is|say|type|insert|use|open) +dot\b)(?:[\w-]+[ ]+(?:slash|hyphen)[ ]+)*[\w-]+[ ]+dot[ ]+(?:py|json|swift|js|ts|yaml|yml|toml|md|csv|html|css|sh|txt)\b"#
    private static let path = #"\b(?:src|lib|bin|usr|etc|tests|docs)(?: +slash +[\w-]+)+\b"#
    private static let extensions = #"\bdot +(py|json|swift|js|ts|yaml|yml|toml|md|csv|html|css|sh|txt)\b"#
    private static func transform(_ input: String, _ pattern: String, _ body: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return input }
        var result = input
        for m in re.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            guard let range = Range(m.range, in: result) else { continue }
            result.replaceSubrange(range, with: body(String(result[range])))
        }
        return result
    }

    static func notation(_ input: String, acronyms: Bool) -> String {
        var text = transform(input, filename) { value in
            let joined = value.replacingOccurrences(of: #" +slash +"#, with: "/", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #" +hyphen +"#, with: "-", options: [.regularExpression, .caseInsensitive])
            guard let dot = joined.range(of: #" +dot +"#, options: [.regularExpression, .caseInsensitive, .backwards]) else { return joined }
            return joined[..<dot.lowerBound] + "." + joined[dot.upperBound...].lowercased()
        }
        text = transform(text, path) { $0.replacingOccurrences(of: #" +slash +"#, with: "/", options: [.regularExpression, .caseInsensitive]) }
        text = transform(text, extensions) { "." + ($0.split(separator: " ").last?.lowercased() ?? "") }
        guard acronyms else { return text }
        // Require separate words so filenames, options and identifiers keep their case.
        text = transform(text, #"\b(?:a p i|s q l|c l i|j s o n|r a g)\b"#) { $0.replacingOccurrences(of: " ", with: "").uppercased() }
        text = transform(text, #"(?<![\w./@:#$-])(?:api|sql|cli|json)(?![\w/@#-]|\.\w)"#) { $0.uppercased() }
        text = transform(text, #"(?<=modular )rag\b|(?<=hybrid )rag\b|\brag(?= (?:pipeline|retrieval|model|architecture|system|query)\b)"#) { $0.uppercased() }
        return text
    }

    static func repairs(_ input: String) -> String {
        // A restart must repeat its imperative. Limit deletion to a short,
        // uncomplicated object at the start of a clause.
        let restart = #"(^|[.!?]\s+)(use|choose|select|install|open) +(?:[a-z]+ ){0,2}[a-z]+(?:\s*[,—–-]\s*| +)wait,? +no(?:\s*[,—–-]\s*| +)\2\b"#
        return input.replacingOccurrences(of: restart, with: "$1$2", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"(?<![\w./-])\b(the|I|we|they|you)(?:[ \t]+\1\b)+(?![\w/-])"#,
                                  with: "$1", options: [.regularExpression, .caseInsensitive])
    }

    static func prosePunctuation(_ input: String) -> String {
        var text = transform(input, #"(?<![\w/@.-])(?:dont|doesnt|didnt|isnt|arent|wasnt|werent|couldnt|wouldnt|shouldnt)(?![\w/@-]|\.\w)"#) { word in
            String(word.dropLast()) + "'" + word.suffix(1)
        }
        text = text.replacingOccurrences(of: #"^(for example|in other words|however)(?= +(?:I|we|you|they|it|this|the)\b)"#,
                                         with: "$1,", options: [.regularExpression, .caseInsensitive])
        // Two independent clauses with an explicit subject and a completed predicate.
        let boundary = #"(^|[.!?] +)((?:the (?:tests?|build|checks?)|it) (?:passed|failed|finished)) +(?=(?:we|they|you|it|the build|the tests) (?:can|should|will|is|are|need)\b)"#
        return text.replacingOccurrences(of: boundary, with: "$1$2. ", options: [.regularExpression, .caseInsensitive])
    }

    static func isQuestion(_ text: String) -> Bool {
        let sentence = text.components(separatedBy: .newlines).last ?? text
        let end = sentence.range(of: #"[.!?] +"#, options: [.regularExpression, .backwards])?.upperBound ?? sentence.startIndex
        return sentence[end...].range(of: #"^(?:(?:can|could|would|should|will|did|do|does|have|has|are|is) (?:i|you|we|they|he|she|it|there|the)\b|(?:what|where|when|why|how|who|which) (?:is|are|was|were|do|does|did|can|could|should|will|would|has|have)\b)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isComposerProse(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep literal shell/code syntax on the technical path. A command name
        // embedded in a natural question does not by itself imply a shell command.
        guard text.range(of: #"[\n`=\[\]{}|<>$\\]|(?:^| )--?\w"#, options: .regularExpression) == nil else { return false }
        return isQuestion(text) || text.range(of: #"^(?:please (?:explain|describe|compare|check|show|help)|(?:explain|describe|compare) (?:why|how|the)|(?:I|we) (?:think|need|want|noticed)|(?:this|the) (?:pipeline|implementation|function|approach) (?:uses|does|has|needs|should))\b"#,
                                               options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func retrievalTerminology(_ input: String) -> String {
        // Require the pipeline and reranking terms in one clause. Rack and grid
        // are legitimate technical vocabulary on their own.
        let pattern = #"\b(modular|hybrid) (?:rack|rag) pipeline\b([^.!?\n]{0,100}?)\b(?:rerunker|reranker|re-ranker)\b"#
        return input.replacingOccurrences(of: pattern, with: "$1 RAG pipeline$2reranker", options: [.regularExpression, .caseInsensitive])
    }

    static func technical(_ raw: String, dictionary: [String]) -> String {
        // Literal source, quoted arguments and shell operators are opaque.
        if raw.range(of: #"[\n\t`'“”\"=(){}\[\];|&<>$\\]"#, options: .regularExpression) != nil { return raw }
        // Only accept named git diff options after an explicit spoken option
        // marker. Ordinary uses of "start" and literal --start stay untouched.
        let spokenDiff = #"^git diff (?:hyphen hyphen|dash dash|double (?:dash|hyphen)) (stat|start|shortstat|numstat|summary|cached|staged|check)\.?$"#
        if raw.range(of: spokenDiff, options: [.regularExpression, .caseInsensitive]) != nil,
           let flag = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased().split(separator: " ").last {
            return "git diff --" + (flag == "start" ? "stat" : String(flag))
        }
        let command = raw.range(of: #"^(?:git|npm|pnpm|yarn|python3?|swift|cargo|docker|cd|ls|cat|mkdir|brew|go)\b"#, options: [.regularExpression, .caseInsensitive])
        if raw.range(of: #"(?:^| )--?\w"#, options: .regularExpression) != nil {
            // A bare option never needs Whisper's closing sentence period.
            // A path, quoted value or unknown command can legitimately end in one.
            if command != nil, raw.range(of: #" --?[a-zA-Z][a-zA-Z0-9-]*\.$"#, options: .regularExpression) != nil {
                return String(raw.dropLast())
            }
            return raw
        }
        switch raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) {
        case "slash", "insert slash", "insert a slash": return "/"
        case "hyphen", "insert hyphen", "insert a hyphen": return "-"
        default: break
        }
        var protected = ProtectedSpans()
        var text = protected.maskTerms(protected.mask(raw), terms: dictionary)
        if command == nil {
            text = DictationLanguage.corrections(repairs(text))
        }
        text = notation(text, acronyms: command == nil)
        if command != nil, let first = text.firstIndex(where: { $0.isWhitespace }) {
            text = text[..<first].lowercased() + text[first...]
        }
        text = protected.restore(text)
        if (command != nil || text.split(whereSeparator: \.isWhitespace).count <= 7),
           text.last == ".", let before = text.dropLast().last, before.isLetter || before.isNumber {
            text.removeLast()
        }
        return text
    }
}
