import Foundation

/// Opaque, per-call markers keep all later transformations outside literal spans.
/// The random prefix prevents input text from impersonating a marker.
struct ProtectedSpans {
    private let prefix = "_KD_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "_"
    private var values: [(String, String)] = []

    mutating func mask(_ text: String) -> String {
        replace(text, pattern: #""[^"]*"|“[^”]*”|‘[^’]*’|(?<![\p{L}\p{N}])'[^'\n]+'(?![\p{L}\p{N}])|https?://[^\s<>"”]+|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}|\b[\p{L}]*[a-z][A-Z][\p{L}]*\b"#)
    }
    mutating func maskTerms(_ text: String, terms: [String]) -> String {
        let terms = terms.filter { !$0.isEmpty }.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern)
        guard !terms.isEmpty else { return text }
        return replace(text, pattern: "\\b(?:" + terms.joined(separator: "|") + ")\\b")
    }
    mutating func maskStructured(_ text: String) -> String {
        var text = text
        for span in CorrectionSpans(text).literalRanges.reversed() {
            guard let range = Range(span, in: text) else { continue }
            let value = String(text[range])
            if value.contains(prefix) { continue }
            let marker = prefix + String(values.count) + "_"
            values.append((marker, value)); text.replaceSubrange(range, with: marker)
        }
        // Numeric compounds may contain letter components too (4:AB, 123/XYZ).
        // Inserting punctuation spaces could turn one operand into separate words
        // and make an ambiguous correction look valid on a subsequent cleanup.
        return replace(text, pattern: #"\b(?:[ap]\.)m\.|(?<![\p{L}\p{N}_])[+−-]?\d+(?:[.,:/-][\p{L}\p{N}_]+)+(?:%|\b)|\b[\p{L}]+[\p{N}]+(?:[-_.][\p{L}\p{N}]+)*\b|\b[\p{L}]+[-_][\p{L}\p{N}_-]+\b"#)
    }
    private mutating func replace(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let value = String(result[range])
            // Previously protected markers must remain atomic.
            if value.contains(prefix) { continue }
            let marker = prefix + String(values.count) + "_"
            values.append((marker, value)); result.replaceSubrange(range, with: marker)
        }
        return result
    }
    func restore(_ text: String) -> String {
        values.reversed().reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
