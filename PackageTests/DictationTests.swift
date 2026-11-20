import Foundation
import MurmurCore
import Testing

private func classified(_ scores: [Double]) -> SpeechEvidence {
    var value = SpeechEvidence()
    for (index, score) in scores.enumerated() {
        let start = Double(index) * 0.25
        value.observe(start: start, end: start + 0.5, confidence: score)
    }
    value.complete()
    return value
}

@Test func singleWordRequiresDeliberateReleaseAndStrongCompleteEvidence() {
    var word = classified([0.97])
    #expect(!word.allowsAutomaticDelivery)
    #expect(!word.allowsHeldDictationDelivery)
    #expect(word.releaseReason(text: "Yes.", frames: []) == "short_word_on_release")
    #expect(word.releaseReason(text: "invented extra words", frames: []) == nil)
    #expect(classified([0.42]).releaseReason(text: "Yes.", frames: []) == nil)
    word.fail()
    #expect(word.releaseReason(text: "Yes.", frames: []) == nil)
}

@Test func consistentSoftSpeechRequiresAdjacentCoverage() {
    #expect(classified([0.76, 0.77, 0.75]).releaseReason(text: "All good.", frames: []) != nil)
    #expect(classified([0.76, 0.42, 0.77]).releaseReason(text: "All good.", frames: []) == nil)
}

@Test func longInteriorPauseNeedsSpeechOnBothSidesAndQuietPCM() {
    let speech = Array(repeating: 0.92, count: 8)
    let pause = Array(repeating: 0.2, count: 18)
    let value = classified(speech + pause + speech)
    let count = Int(value.analyzedThrough * AudioTools.rate)
    let quiet = AudioTools.frames(Array(repeating: 0.0002, count: count))
    #expect(!value.allowsHeldDictationDelivery)
    #expect(value.releaseReason(text: "Two phrases", frames: quiet) == "verified_interior_pause_on_release")
    #expect(value.releaseReason(text: "Two phrases", frames: []) == nil)
    #expect(value.releaseReason(text: "Two phrases", frames: AudioTools.frames(Array(repeating: 0.1, count: count))) == nil)
    #expect(classified(speech + pause).releaseReason(text: "No trailing authorization", frames: quiet) == nil)
}

@Test func mixedNoiseNeverQualifiesOnRelease() {
    let speech = Array(repeating: 0.92, count: 20)
    let noise = Array(repeating: 0.42, count: 240)
    for scores in [noise, speech + noise, noise + speech, speech + noise + speech] {
        let evidence = classified(scores)
        #expect(!evidence.allowsAutomaticDelivery)
        #expect(!evidence.allowsHeldDictationDelivery)
        #expect(evidence.releaseReason(text: "Yes", frames: []) == nil)
    }
}

@Test func cursorJoinsAndPunctuation() {
    func insert(_ raw: String, _ prefix: String, _ suffix: String = "", mode: DictationMode = .dictate) -> String {
        let caret = CaretContext(text: prefix + suffix, selection: NSRange(location: prefix.utf16.count, length: 0))
        return RuleCleanup().apply(raw, context: TextContext(dictionary: ["Priya", "PostgreSQL"], mode: mode, caret: caret))
    }
    #expect(insert("good morning", "Hello.") == " Good morning.")
    #expect(insert("Good morning.", "Hello. ") == "Good morning.")
    #expect(insert("Good morning.", "I said,") == " good morning")
    #expect(insert("Another option.", "or") == " another option")
    #expect(insert("Avery.", "Avery said to ask") == " Avery")
    #expect(insert("the migration.", "Review", "tomorrow.") == " the migration ")
    #expect(insert("the migration full stop.", "Review") == " the migration.")
    #expect(insert("the migration insert a period.", "Review") == " the migration.")
    #expect(insert("period", "Review") == ".")
    #expect(insert("the grace period.", "Extend") == " the grace period")
    #expect(insert("Priya.", "ask", ", please") == " Priya")
    #expect(insert("PostgreSQL", "Review ") == "PostgreSQL")
    #expect(insert("good morning", "Hello.", mode: .exact) == "good morning")
    #expect(insert("hello", "okay\n") == "Hello.")
    let caret = CaretContext(text: "🌟 Ask Sam today", selection: NSRange(location: 7, length: 3))
    #expect(caret?.prefix == "🌟 Ask ")
    #expect(caret?.suffix == " today")
}

@Test func hintPriorityAndBudget() throws {
    let text = String(repeating: "Distant ", count: 100) + "OAuth2 whisper.cpp"
    let caret = CaretContext(text: text, selection: NSRange(location: text.utf16.count - 11, length: 0))
    let dictionary = (0..<100).map { "CustomTerm" + String($0) }
    let hints = SpeechRequest.vocabulary(dictionary, near: caret)
    #expect(hints.first == dictionary.first)
    #expect(hints.prefix(4).contains("OAuth2"))
    #expect(hints.prefix(4).contains("whisper.cpp"))
    let splitWord = CaretContext(text: "use PostgreSQL here", selection: NSRange(location: 9, length: 0))
    #expect(SpeechRequest.vocabulary([], near: splitWord).first == "PostgreSQL")
    #expect(hints.count == 64)
    #expect(hints.joined(separator: ", ").utf8.count <= 1024)
    #expect(SpeechRequest.vocabulary(dictionary, near: nil) == Array(dictionary.prefix(64)))
    let ordinary = (0..<70).map { "alpha" + String(repeating: "a", count: $0) }
    let distinctive = SpeechRequest.vocabulary(ordinary + ["Zelda", "whisper.cpp"], near: nil)
    #expect(distinctive.prefix(2) == ["Zelda", "whisper.cpp"])
    #expect(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).contextEnabled)
    #expect(try !JSONDecoder().decode(Preferences.self, from: Data(#"{"contextEnabled":false}"#.utf8)).contextEnabled)
}

@Test func uncertainHoldNeedsCompletedPositiveSpeech() {
    #expect(!classified([0.2, 0.2]).allowsUncertainShortRelease)
    #expect(!classified([0.79]).allowsUncertainShortRelease)
    #expect(classified([0.82]).allowsUncertainShortRelease)
    #expect(!classified(Array(repeating: 0.82, count: 14)).allowsUncertainShortRelease)
    var failed = classified([0.95])
    failed.fail()
    #expect(!failed.allowsUncertainShortRelease)
}

@Test func punctuationRequiresZeroWordEdits() {
    func accepts(_ new: String, _ old: String, _ dictionary: [String] = []) -> Bool {
        CleanupFidelity.accepts(new, baseline: old, dictionary: dictionary)
    }
    #expect(accepts("If it works, ship it. We shouldn't wait.", "If it works ship it we shouldnt wait."))
    #expect(!accepts("Read the SQL query?", "Read the SQL query."))
    #expect(accepts("Can we ship?", "Can we ship."))
    #expect(!accepts("We could ship.", "We should ship."))
    #expect(!accepts("Ship today.", "Ship it today."))
    #expect(!accepts("Ship ship it.", "Ship it."))
    #expect(!accepts("Ship it now.", "Now ship it."))
    #expect(!accepts("Use config. json.", "Use config.json."))
    #expect(!accepts("Ship at 1.25.", "Ship at 125."))
    #expect(!accepts("New, York.", "New York.", ["New York"]))
    #expect(!accepts("Run `git status.`", "Run `git status`"))
    #expect(!accepts("It's ready.", "Its ready."))
    #expect(!accepts("Use --dry run.", "Use --dry-run."))
}

@Test func developerAndProseFormatting() {
    let rules = RuleCleanup()
    #expect(rules.apply("use linear wait no use hybrid search") == "Use hybrid search.")
    #expect(rules.apply("if the tests passed we can deploy").contains("passed. We") == false)
    #expect(rules.apply("the j s o n file") == "The JSON file.")
    for bundle in ["com.openai.codex", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal"] {
        let dev = TextContext(application: bundle)
        #expect(rules.apply("Git status.", context: dev) == "git status")
        #expect(rules.apply("git diff --stat.", context: dev) == "git diff --stat")
        #expect(rules.apply("git add .", context: dev) == "git add .")
        #expect(rules.apply("python src slash main dot py.", context: dev) == "python src/main.py")
        #expect(rules.apply("open config dot JSON", context: dev) == "open config.json")
        #expect(rules.apply("my hyphen file dot py", context: dev) == "my-file.py")
        #expect(rules.apply("insert slash", context: dev) == "/")
        #expect(rules.apply("hyphen", context: dev) == "-")
        #expect(rules.apply("let json = api", context: dev) == "let json = api")
    }
    for bundle in ["com.apple.Notes", "com.apple.Safari", "com.apple.iWork.Pages"] {
        let prose = TextContext(application: bundle)
        #expect(rules.apply("use a rag to clean the desk", context: prose) == "Use a rag to clean the desk.")
        #expect(rules.apply("we should slash costs", context: prose) == "We should slash costs.")
        #expect(rules.apply("use the dot py extension", context: prose) == "Use the .py extension.")
        #expect(rules.apply("does the cli return json", context: prose) == "Does the CLI return JSON?")
        #expect(rules.apply("I think I I need the the logs", context: prose) == "I think I need the logs.")
        #expect(rules.apply("we had had enough", context: prose) == "We had had enough.")
    }
}

@Test func codexSpokenCommandAndTechnicalQuestions() {
    let rules = RuleCleanup()
    let codex = TextContext(application: "com.openai.codex")
    for flag in ["stat", "start"] {
        #expect(rules.apply("git diff hyphen hyphen " + flag, context: codex) == "git diff --stat")
    }
    #expect(rules.apply("git diff --start", context: codex) == "git diff --start")
    #expect(rules.apply("npm start", context: codex) == "npm start")
    #expect(rules.apply("Why does the modular rack pipeline use a separate rerunker?", context: codex) == "Why does the modular RAG pipeline use a separate reranker?")
    #expect(rules.apply("why does the modular rack pipeline use steel", context: codex) == "Why does the modular rack pipeline use steel?")
    #expect(rules.apply("can you explain why git status is slow", context: codex) == "Can you explain why git status is slow?")
    #expect(rules.apply("explain how the grid status is calculated", context: codex) == "Explain how the grid status is calculated.")
    #expect(rules.apply("git diff hyphen hyphen start", context: TextContext(mode: .exact)) == "git diff hyphen hyphen start")
}
