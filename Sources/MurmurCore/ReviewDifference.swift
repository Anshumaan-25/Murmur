import Foundation

/// A bounded, linear comparison highlighting the changed passage in both versions.
/// Common text between multiple edits can also be highlighted; this is not a fact checker.
public struct ReviewDifference: Sendable {
    public let original: NSRange
    public let result: NSRange
    public var unchanged: Bool { original.length == 0 && result.length == 0 }

    public static func between(_ original: String, _ result: String) -> ReviewDifference {
        guard original != result else { return ReviewDifference(original: NSRange(location: 0, length: 0), result: NSRange(location: 0, length: 0)) }
        let before = Array(original), after = Array(result)
        var prefix = 0, suffix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
        func span(_ text: [Character]) -> NSRange {
            var start = prefix, end = text.count - suffix
            // Include whole words/values so a changed digit or negation is easy to inspect.
            while start > 0, start < text.count, !text[start].isWhitespace, !text[start - 1].isWhitespace { start -= 1 }
            while end < text.count, end > 0, !text[end - 1].isWhitespace, !text[end].isWhitespace { end += 1 }
            let location = String(text[..<start]).utf16.count
            return NSRange(location: location, length: String(text[start..<end]).utf16.count)
        }
        return ReviewDifference(original: span(before), result: span(after))
    }
}
