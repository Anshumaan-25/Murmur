import Foundation

/// Lexical connected components, shared by every correction branch and by final
/// punctuation protection. Unknown punctuation/symbols connect by default;
/// only explicit prose delimiters and supported unary decorations separate them.
struct CorrectionSpans {
    private struct Token {
        let text: String
        let range: NSRange
        let atom: Bool
        var digits: Bool { atom && text.allSatisfy(\.isNumber) }
        var identifier: Bool {
            text.contains(where: \.isNumber) || (text.count > 1 && text.allSatisfy { $0.isUppercase })
        }
    }
    let ranges: [NSRange]
    let literalRanges: [NSRange]
    init(_ text: String) {
        var tokens: [Token] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text[cursor].isWhitespace { cursor = text.index(after: cursor); continue }
            let start = cursor
            let atom = text[cursor].isLetter || text[cursor].isNumber
            cursor = text.index(after: cursor)
            if atom {
                while cursor < text.endIndex {
                    let character = text[cursor]
                    if character.isLetter || character.isNumber { cursor = text.index(after: cursor); continue }
                    // Keep ordinary apostrophized words atomic, not symbol spans.
                    let next = text.index(after: cursor)
                    if "'’".contains(character), text[text.index(before: cursor)].isLetter,
                       next < text.endIndex, text[next].isLetter { cursor = next; continue }
                    break
                }
            }
            tokens.append(Token(text: String(text[start..<cursor]), range: NSRange(start..<cursor, in: text), atom: atom))
        }
        func gap(_ left: Int, _ right: Int) -> Bool { NSMaxRange(tokens[left].range) < tokens[right].range.location }
        func delimiter(_ index: Int) -> Bool {
            let token = tokens[index]
            guard !token.atom, ".,!?;:".contains(token.text) else { return false }
            // A terminal mark ends a sentence even when ASR leaves a space before it.
            if index + 1 == tokens.count { return true }
            // Preserve sentence-spacing repair for "7.05%.Keep ...". A percent
            // amount followed by a sentence mark and title-case prose is complete.
            if index > 1, ".!?".contains(token.text), tokens[index - 1].text == "%",
               tokens[index - 2].digits, tokens[index + 1].atom,
               tokens[index + 1].text.first?.isUppercase == true,
               tokens[index + 1].text.dropFirst().first?.isLowercase == true { return true }
            guard token.text != ":", gap(index, index + 1), tokens[index + 1].atom else { return false }
            // Attached prose punctuation followed by ordinary prose is a boundary.
            if index > 0, !gap(index - 1, index), !tokens[index + 1].identifier { return true }
            // Spoken punctuation often arrives with spaces on both sides. Numeric
            // or ID components remain connected; ordinary prose can still format.
            return index > 0 && tokens[index - 1].atom && !tokens[index - 1].identifier && !tokens[index + 1].identifier
        }
        func unaryPrefix(_ index: Int) -> Bool {
            guard !tokens[index].atom, ["+", "-", "−"].contains(tokens[index].text),
                  index + 1 < tokens.count, tokens[index + 1].digits, !gap(index, index + 1) else { return false }
            return index == 0 || (gap(index - 1, index) && !tokens[index - 1].identifier)
        }
        func suffixBeforeProse(_ index: Int) -> Bool {
            index > 0 && index + 1 < tokens.count && tokens[index].text == "%" &&
            tokens[index - 1].digits && !gap(index - 1, index) && gap(index, index + 1) &&
            tokens[index + 1].atom && !tokens[index + 1].identifier
        }
        func proseBoundary(_ index: Int) -> Bool {
            guard !tokens[index].atom else { return false }
            let category = tokens[index].text.unicodeScalars.first?.properties.generalCategory
            // Wrappers must not hide surrounding prose from capitalization.
            if category == .openPunctuation || category == .closePunctuation { return true }
            if tokens[index].text == ":" || category == .dashPunctuation {
                func identifierLike(_ token: Token) -> Bool { token.identifier || token.text.first?.isUppercase == true }
                return index == 0 || index + 1 == tokens.count ||
                    !(identifierLike(tokens[index - 1]) && identifierLike(tokens[index + 1]))
            }
            return false
        }
        func components(formatting: Bool) -> [NSRange] {
            var spans: [NSRange] = []
            var first = 0
            for index in tokens.indices {
                let last = index + 1 == tokens.count
                let connected: Bool
                if last { connected = false }
                else if delimiter(index) || delimiter(index + 1) || unaryPrefix(index + 1) || suffixBeforeProse(index) { connected = false }
                else if formatting && (proseBoundary(index) || proseBoundary(index + 1)) { connected = false }
                else if formatting && tokens[index].atom && !tokens[index].identifier && gap(index, index + 1) &&
                            tokens[index + 1].text.unicodeScalars.first?.properties.generalCategory == .currencySymbol { connected = false }
                else if !tokens[index].atom || !tokens[index + 1].atom { connected = true }
                else { connected = tokens[index].digits && tokens[index + 1].digits }
                if !connected {
                    if index > first && (!formatting || tokens[first...index].contains(where: \.identifier)) {
                        spans.append(NSRange(location: tokens[first].range.location, length: NSMaxRange(tokens[index].range) - tokens[first].range.location))
                    }
                    first = index + 1
                }
            }
            return spans
        }
        ranges = components(formatting: false)
        literalRanges = components(formatting: true)
    }
    func containsWhole(_ candidate: NSRange) -> Bool {
        func crosses(_ boundary: Int) -> Bool {
            var low = 0, high = ranges.count
            while low < high {
                let middle = (low + high) / 2
                if ranges[middle].location < boundary { low = middle + 1 } else { high = middle }
            }
            return low > 0 && NSMaxRange(ranges[low - 1]) > boundary
        }
        return !crosses(candidate.location) && !crosses(NSMaxRange(candidate))
    }
}
