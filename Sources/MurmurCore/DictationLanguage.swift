import Foundation

public enum DictationLanguage {
    private static let units: [String: Int] = ["zero":0,"oh":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19,"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90]
    private static func replace(_ text: String, pattern: String, template: String, insensitive: Bool = true) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : []) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
    private static func replaceOperands(_ text: String, pattern: String, template: String, insensitive: Bool = true) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : []) else { return text }
        var output = text
        let spans = CorrectionSpans(text)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            guard spans.containsWhole(match.range) else { continue }
            output.replaceSubrange(range, with: regex.replacementString(for: match, in: text, offset: 0, template: template))
        }
        return output
    }
    public static func corrections(_ input: String) -> String {
        var text = input
        let cue = #"(?:(?:actually|no|sorry)\s*,?\s+make\s+that)"#
        // Recognize complete whitespace-delimited operands, never a numeric substring
        // inside an ID, date, version, currency expression or unknown notation. Only
        // sentence punctuation followed by whitespace/end may terminate an operand.
        let start = #"(?<!\S)"#
        let end = #"(?=$|\s|[.,!?;:](?=\s|$))"#
        let correction = #"[.,]?\s+"# + cue + #"\s+"#
        // A complete pair of time values, including meridiem, survives ASR sentence boundaries.
        let time = #"(1[0-2]|[1-9])[.:]([0-5][0-9])[ \t]*([ap])\.?m"#
        text = replaceOperands(text, pattern: start + time + #"\.?"# + correction + time + end, template: "$4:$5 $6M")
        text = replace(text, pattern: #"\b(\d{1,2}:\d{2}) pM\b"#, template: "$1 PM")
        text = replace(text, pattern: #"\b(\d{1,2}:\d{2}) aM\b"#, template: "$1 AM")
        // Conservative title-case names; all-caps ID components are not names.
        let name = #"[A-Z][\p{Ll}'’]+(?:-[A-Z][\p{Ll}'’]+)?"#
        let names = start + #"((?i:in|to|from|with)\s+)("# + name + #"(?:\s+"# + name + #"){0,3})\s*,?\s*(?i:"# + cue + #")\s+("# + name + #"(?:\s+"# + name + #"){0,3})"# + end
        text = replaceOperands(text, pattern: names, template: "$1$3", insensitive: false)
        let weekday = "(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"
        text = replaceOperands(text, pattern: start + weekday + correction + "(" + weekday + ")" + end, template: "$1")
        let repeatedQuantity = start + #"\d+(?:,\d{3})*[ \t]+([\p{L}]+),[ \t]*sorry,[ \t]*(\d+(?:,\d{3})*[ \t]+\1)"# + end
        text = replaceOperands(text, pattern: repeatedQuantity, template: "$2")
        let scalar = #"[+−-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#
        // Match the same kind on both sides. Unsupported structured values remain
        // literal, rather than guessing whether a fragment replaces a whole value.
        let operands = [scalar, scalar + "%", #"\d+(?:st|nd|rd|th)"#,
                        #"(?:[01]?\d|2[0-3]):[0-5]\d"#, #"(?:1[0-2]|[1-9])[ \t]+[ap]m"#]
        for operand in operands {
            text = replaceOperands(text, pattern: start + operand + correction + "(" + operand + ")" + end, template: "$1")
        }

        return text
    }
    public static func numbers(_ input: String) -> String {
        var text = input
        let hour = "(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]{1,2})"
        let minute = "(?:ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty)(?:[ -]+(?:one|two|three|four|five|six|seven|eight|nine))?"
        if let regex = try? NSRegularExpression(pattern: "\\b(at|by|around|until|before|after|from|actually(?:\\s+make\\s+that)?|no\\s+make\\s+that|sorry\\s+make\\s+that)\\s+(" + hour + ")\\s+(" + minute + "|(?:oh|zero)\\s+(?:one|two|three|four|five|six|seven|eight|nine))\\b", options: [.caseInsensitive]) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let full = Range(match.range, in: text), let h = Range(match.range(at: 2), in: text), let m = Range(match.range(at: 3), in: text), let prep = Range(match.range(at: 1), in: text) else { continue }
                let hourValue = Int(text[h]) ?? units[text[h].lowercased()] ?? 0
                let minuteValue = text[m].lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).reduce(0) { $0 + (units[String($1)] ?? 0) }
                if (1...12).contains(hourValue), minuteValue < 60 { text.replaceSubrange(full, with: String(text[prep]) + " " + String(format: "%d:%02d", hourValue, minuteValue)) }
            }
        }
        text = replace(text, pattern: #"\ba\s+(hundred|thousand|million)\b"#, template: "one $1")
        let digit = "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)"
        let digits = digit + "(?:[ \\t-]+" + digit + ")*"
        let spokenDigits = #"\b(point[ \t]+|(?:code|ID|PIN|identifier)[ \t]+(?:is[ \t]+)?)("# + digits + #")\b(?![ \t]+(?:hundred|thousand|million)\b)"#
        if let regex = try? NSRegularExpression(pattern: spokenDigits, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let full = Range(match.range, in: text), let prefix = Range(match.range(at: 1), in: text),
                      let group = Range(match.range(at: 2), in: text) else { continue }
                let joined = text[group].lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" })
                    .compactMap { units[String($0)].map(String.init) }.joined()
                text.replaceSubrange(full, with: String(text[prefix]) + joined)
            }
        }
        let vocabulary = units.keys.filter { $0 != "oh" }.sorted().joined(separator: "|")
        let expression = "\\b(?:" + vocabulary + ")(?:[ -]+(?:" + vocabulary + "|hundred|thousand|million|and(?=[ -]+(?:" + vocabulary + "))))*\\b"
        if let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let original = String(text[range]); let tail = String(text[range.upperBound...])
                // Ambiguous standalone “one” is prose unless a quantity is explicit.
                if original.lowercased() == "one", tail.range(of: #"^\s+(?:invoice|receipt|ticket|item|day|week|month|year|hour|minute|second|dollar|rupee|percent|point)\b"#, options: [.regularExpression, .caseInsensitive]) == nil { continue }
                text.replaceSubrange(range, with: renderNumber(original))
            }
        }
        text = replace(text, pattern: #"\b(\d+)\s+point\s+(\d+)\b"#, template: "$1.$2")
        text = replace(text, pattern: #"\b(?:minus|negative)\s+(\d+(?:\.\d+)?)\b"#, template: "-$1")
        text = replace(text, pattern: #"\b(\d+(?:\.\d+)?)\s+percent\b"#, template: "$1%")
        text = replace(text, pattern: #"\b(\d{1,2}(?::\d{2})?)\s+p\s*m\b"#, template: "$1 PM")
        text = replace(text, pattern: #"\b(\d{1,2}(?::\d{2})?)\s+a\s*m\b"#, template: "$1 AM")
        let ordinals = ["first":"1st", "second":"2nd", "third":"3rd", "fourth":"4th", "fifth":"5th", "sixth":"6th", "seventh":"7th", "eighth":"8th", "ninth":"9th", "tenth":"10th", "eleventh":"11th", "twelfth":"12th", "thirteenth":"13th", "fourteenth":"14th", "fifteenth":"15th", "sixteenth":"16th", "seventeenth":"17th", "eighteenth":"18th", "nineteenth":"19th", "twentieth":"20th"]
        let months = "(?:January|February|March|April|May|June|July|August|September|October|November|December)"
        for (spoken, digits) in ordinals { text = replace(text, pattern: "\\b(" + months + ")\\s+" + spoken + "\\b", template: "$1 " + digits) }
        return text
    }
    private static func renderNumber(_ phrase: String) -> String {
        let tokens = phrase.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        if !tokens.contains(where: { ["hundred", "thousand", "million"].contains($0) }), tokens.contains("and") {
            return tokens.split(separator: "and").map { renderNumber($0.joined(separator: " ")) }.joined(separator: " and ")
        }
        if tokens.count > 1, tokens.allSatisfy({ (units[$0] ?? 100) < 10 }) { return tokens.map { String(units[$0]!) }.joined() }
        var group = 0; var total = 0; var previous: Int?; var largestScale = Int.max
        for token in tokens {
            if token == "and" { continue }
            if token == "hundred" { guard group > 0 && group < 10 else { return phrase }; group *= 100; previous = nil }
            else if token == "thousand" || token == "million" {
                let scale = token == "thousand" ? 1000 : 1_000_000
                guard scale < largestScale else { return phrase }; total += max(group, 1) * scale; group = 0; previous = nil; largestScale = scale
            } else if let value = units[token] {
                if let prior = previous, !(prior >= 20 && prior % 10 == 0 && value < 10) { return tokens.map { units[$0].map(String.init) ?? $0 }.joined(separator: " ") }
                group += value; previous = value
            }
        }
        return String(total + group)
    }
}
