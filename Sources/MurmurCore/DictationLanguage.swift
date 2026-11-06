import Foundation

public enum DictationLanguage {
    private static let units: [String: Int] = ["zero":0,"oh":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19,"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90]
    private static func replace(_ text: String, pattern: String, template: String, insensitive: Bool = true) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : []) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
    public static func corrections(_ input: String) -> String {
        var text = input
        let names = #"(\b(?i:in|to|from|with)\s+)([A-Z][\p{L}'’-]+(?:\s+[A-Z][\p{L}'’-]+){0,3})\s*,?\s*(?i:actually(?:\s+make\s+that)?|no\s+make\s+that|sorry\s+make\s+that)\s+([A-Z][\p{L}'’-]+(?:\s+[A-Z][\p{L}'’-]+){0,3})"#
        text = replace(text, pattern: names, template: "$1$3", insensitive: false)
        let clock = #"(\b(?:at|by|around|until|before|after)\s+)(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*,?\s*(?:actually(?:\s+make\s+that)?|no(?:\s+make\s+that)?|sorry(?:\s+make\s+that)?)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#
        text = replace(text, pattern: clock, template: "$1$3")
        let weekday = "(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"
        text = replace(text, pattern: "\\b" + weekday + "\\s*,?\\s*(?:actually(?:\\s+make\\s+that)?|no(?:\\s+make\\s+that)?|sorry(?:\\s+make\\s+that)?)\\s+(" + weekday + ")\\b", template: "$1")
        let repeatedQuantity = #"(?<![\w.,$+−-])\d+(?:,\d{3})*[ \t]+([\p{L}]+),[ \t]*sorry,[ \t]*(\d+(?:,\d{3})*[ \t]+\1)\b(?!['’-])"#
        text = replace(text, pattern: repeatedQuantity, template: "$2")
        let number = #"[-+]?\d+(?:[.:]\d+)*(?:%|st|nd|rd|th)?"#
        text = replace(text, pattern: "(" + number + ")\\s*,?\\s*actually(?:\\s+make\\s+that)?\\s+(" + number + ")", template: "$2")
        let word = #"(?:[-+]?\d+(?:[.:]\d+)*|[\p{L}][\p{L}'’-]*)"#
        text = replace(text, pattern: "(" + word + ")\\s*,?\\s*(?:actually\\s+make\\s+that|no\\s+make\\s+that|sorry\\s+make\\s+that)\\s+(" + word + ")", template: "$2")
        text = replace(text, pattern: "(" + word + ")\\s*,\\s*actually\\s*,?\\s+(" + word + ")", template: "$2")
        text = replace(text, pattern: #"^.+?[,;.!?]\s*(?:scratch that|never mind)[,;.!?]\s*"#, template: "")
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
        let vocabulary = units.keys.filter { $0 != "oh" }.sorted().joined(separator: "|")
        let expression = "\\b(?:" + vocabulary + ")(?:[ -]+(?:" + vocabulary + "|hundred|thousand|million|and(?=[ -]+(?:" + vocabulary + "))))*\\b"
        if let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let original = String(text[range]); let tail = String(text[range.upperBound...])
                if original.lowercased() == "one", tail.range(of: #"^\s+(?:of|another)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
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
