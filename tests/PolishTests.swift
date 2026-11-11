import Foundation
import MurmurCore

func polishProtocolChecks() async {
    // Exercise the real local classifier using synthetic PCM, without a microphone.
    let silentEvidence = await SoundSpeechMonitor.assess(AudioTools.frames(Array(repeating: 0, count: 32_000)))
    expect(!silentEvidence.heardSpeech && !silentEvidence.allowsAutomaticDelivery, "digital silence cannot authorize delivery through the classifier")
    let monitor = SoundSpeechMonitor()
    monitor.append(Array(repeating: 0.01, count: 32_001))
    let overflowEvidence = await monitor.finish()
    expect(!overflowEvidence.allowsAutomaticDelivery && !overflowEvidence.heardSpeech, "classifier queue overflow fails closed")
    let cancelledMonitor = SoundSpeechMonitor(); cancelledMonitor.cancel()
    cancelledMonitor.append(Array(repeating: 0.1, count: 640))
    let cancelledEvidence = await cancelledMonitor.finish()
    expect(!cancelledEvidence.allowsAutomaticDelivery, "cancelled classifier cannot authorize a later session")
    let structured = "Reference 123/456 actually make that 789."
    let optional = await SystemCleanup(budget: 0.01).attempt(structured, context: TextContext())
    expect(optional.text == structured, "optional cleanup provider preserves ambiguous structured correction")
    expect(!CleanupFidelity.accepts("Reference 123/789.", baseline: structured, dictionary: []), "optional model gate rejects the original composite-ID regression")
    for raw in ["Reference 123 : 456 actually make that 789.", "Work with Jordan actually make that Priya | 007."] {
        let result = await SystemCleanup(budget: 0.01).attempt(raw, context: TextContext())
        expect(result.text == raw, "optional cleanup retains complete connected operands")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("synthetic-decoder")
        try Data(#"""
        #!/usr/bin/python3
        import sys,struct,os
        raw=sys.stdin.buffer.read()
        magic=raw[:4]
        version,prompt_bytes,audio_bytes=struct.unpack('<III',raw[4:16])
        prompt=raw[16:16+prompt_bytes].decode()
        audio=raw[16+prompt_bytes:]
        assert magic==b'KDSP' and version==1 and prompt=='FixtureCanaryName'
        assert len(audio)==audio_bytes and audio.startswith(b'RIFF')
        assert 'FixtureCanaryName' not in ' '.join(sys.argv)
        assert 'FixtureCanaryName' not in str(dict(os.environ))
        assert '--keydown-request-v1' in sys.argv
        print('Private vocabulary integration passed.')
        """#.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = ExecutableSpeechProvider(executable: executable, model: executable, privateProtocol: true)
        let result = try await provider.transcribe(AudioTools.frames(Array(repeating: 0.01, count: 640)), language: "en-IN", vocabulary: ["FixtureCanaryName"])
        expect(result.text == "Private vocabulary integration passed.", "provider/process/parser integration keeps hints off argv and environment")
        try Data("#!/bin/sh\ncat >/dev/null\nprintf '[BLANK_AUDIO]\\n'\n".utf8).write(to: executable)
        do { _ = try await provider.transcribe(AudioTools.frames([0.001]), language: "en", vocabulary: []); expect(false, "bundled no-speech output rejected") }
        catch MurmurError.empty {} catch { expect(false, "no-speech has the empty-audio outcome") }
        let custom = ExecutableSpeechProvider(executable: executable, model: executable)
        let literal = try await custom.transcribe(AudioTools.frames([0.001]), language: "en", vocabulary: [])
        expect(literal.text == "[BLANK_AUDIO]", "custom provider text is not silently rewritten")
    } catch { expect(false, "private vocabulary integration: \(error)") }
}

func polishTextChecks() {
    mixedAudioEvidenceChecks()
    structuredCorrectionChecks()
    let mediaDefaults = try? JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    expect(mediaDefaults?.pauseMedia == true, "media pause defaults on for existing preferences")
    var mediaDisabled = Preferences(); mediaDisabled.pauseMedia = false
    let mediaRoundTrip = try? JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(mediaDisabled))
    expect(mediaRoundTrip?.pauseMedia == false, "media pause opt out survives saving")
    expect(mediaDefaults?.pasteUncertainOnHoldRelease == false, "direct held delivery is opt-in")
    var direct = Preferences()
    direct.pasteUncertainOnHoldRelease = true
    let directRoundTrip = try? JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(direct))
    expect(directRoundTrip?.pasteUncertainOnHoldRelease == true, "direct held delivery preference survives saving")

    expect(SpeechEvidence().deliveryBlock(held: false) == "incomplete", "uncompleted speech diagnostic names incomplete analysis")
    var failedDiagnostic = SpeechEvidence(); failedDiagnostic.fail()
    expect(failedDiagnostic.deliveryBlock(held: true) == "analysis_failed", "failed speech diagnostic distinguishes failure from quiet speech")
    var activity = SpeechEvidence()
    activity.observe(start: 0, end: 0.5, confidence: 0.95)
    activity.observe(start: 0.25, end: 0.75, confidence: 0.95)
    expect(activity.heardSpeech, "speech from the first sample does not become a noise baseline")
    for i in 2...8 { activity.observe(start: Double(i) * 0.25, end: Double(i) * 0.25 + 0.5, confidence: 0.1) }
    expect(activity.silence >= 1.5, "non-speech after immediate speech advances silence completion")
    expect(!activity.allowsAutomaticDelivery, "unfinished analysis cannot authorize delivery")
    activity.complete()
    expect(activity.allowsAutomaticDelivery, "completed confident speech can authorize delivery")
    expect(activity.deliveryBlock(held: false) == "ready", "eligible evidence reports ready")
    var ambiguousActivity = SpeechEvidence()
    ambiguousActivity.observe(start: 0, end: 0.5, confidence: 0.95)
    for i in 1...6 { ambiguousActivity.observe(start: Double(i) * 0.25, end: Double(i) * 0.25 + 0.5, confidence: 0.5) }
    expect(ambiguousActivity.silence == 0, "uncertain sound is not proof of silence and cannot truncate quiet speech")
    var classifiedSilence = SpeechEvidence()
    classifiedSilence.observe(start: 0, end: 0.5, confidence: 0.95)
    for i in 1...8 { classifiedSilence.observe(start: Double(i) * 0.25, end: Double(i) * 0.25 + 0.5, confidence: 0.205) }
    expect(classifiedSilence.silence >= 1.5, "measured classifier digital-silence score permits hands-free completion")
    var noise = SpeechEvidence()
    for i in 0..<240 { noise.observe(start: Double(i) * 0.25, end: Double(i) * 0.25 + 0.5, confidence: 0.42) }
    noise.complete()
    expect(!noise.heardSpeech && !noise.allowsAutomaticDelivery, "noise cannot authorize delivery or reset speech clock")
    var failedAnalysis = activity; failedAnalysis.fail()
    expect(!failedAnalysis.allowsAutomaticDelivery && !failedAnalysis.heardSpeech, "analysis failure revokes delivery and hands-free authority")
    var short = SpeechEvidence(); short.observe(start: 0, end: 0.5, confidence: 0.95); short.complete()
    expect(!short.allowsAutomaticDelivery, "one isolated positive window remains reviewable")
    var malformed = SpeechEvidence(); malformed.observe(start: 0, end: 0.5, confidence: .nan); malformed.complete()
    expect(!malformed.allowsAutomaticDelivery, "invalid confidence fails closed")
    var gap = SpeechEvidence(); gap.observe(start: 1, end: 1.5, confidence: 0.99); gap.complete()
    expect(!gap.heardSpeech && !gap.allowsAutomaticDelivery, "missing classifier coverage fails closed")

    for input in ["Do not actually make that payment.", "I did not actually make that payment.", "Keep invoice AB-007 actually make that AB-070.", "I am the only one who agrees.", "One Direction performed in New York."] {
        expect(RuleCleanup().apply(input) == input, "adversarial literal preservation: \(input)")
    }
    for (input, output) in [("spell A B hyphen zero zero seven.", "AB-007"), ("Spell AB-007.", "AB-007"), ("spell three dot fourteen dot two.", "3.14.2"), ("spell one dot", "1.")] {
        expect(RuleCleanup().apply(input, context: TextContext(mode: .exact)) == output, "spelling decoder integration representation: \(input)")
    }
    for (before, after) in [("We cannot approve.", "We can approve."), ("The fee is fifty rupees.", "The fee is sixty rupees.")] {
        expect(!RewriteFidelity.accepts(after, selected: before), "edit fidelity rejects changed polarity or amount")
    }

    let difference = ReviewDifference.between("Pay ₹1,205 to Priya 👩🏽‍💻.", "Pay ₹12,500 to Priya 👩🏽‍💻.")
    expect(("Pay ₹1,205 to Priya 👩🏽‍💻." as NSString).substring(with: difference.original) == "₹1,205", "review highlights the original amount")
    expect(("Pay ₹12,500 to Priya 👩🏽‍💻." as NSString).substring(with: difference.result) == "₹12,500", "review highlights the changed amount")
    expect(ReviewDifference.between("👩🏽‍💻 Keep AB-007.", "👩🏽‍💻 Keep AB-007.").unchanged, "unchanged Unicode text has no review highlight")
    let deletion = ReviewDifference.between("Never share AB-007.", "Share AB-007.")
    expect(deletion.original.length > 0 && deletion.result.length > 0, "review exposes a deleted negation")
    do {
        let request = try SpeechRequest.encode(wav: Data([1, 2, 3, 4]), vocabulary: ["Siobhán", "PostgreSQL", "bad\nterm"])
        expect(String(decoding: request.prefix(4), as: UTF8.self) == "KDSP", "private speech request has a versioned header")
        expect(String(decoding: request, as: UTF8.self).contains("Siobhán, PostgreSQL"), "vocabulary is carried inside private input")
        expect(!String(decoding: request, as: UTF8.self).contains("bad\nterm"), "control characters cannot enter recognition hints")
        expect(request.suffix(4) == Data([1, 2, 3, 4]), "PCM container follows framed metadata unchanged")
    } catch { expect(false, "speech request encoding succeeds") }
    let quiet = AudioTools.frames(Array(repeating: Float(0.001), count: 16000))
    expect(AudioTools.trimmed(quiet).count == quiet.count, "quiet captured audio reaches recognition")
    expect(AudioTools.trimmed(AudioTools.frames(Array(repeating: 0, count: 16000))).isEmpty, "digital silence stays empty")
    expect(AudioSignal.classify(rms: 0.001, peak: 0.002, received: true) == .quiet, "quiet input has useful feedback")
    expect(AudioSignal.classify(rms: 0.3, peak: 1, received: true) == .clipped, "clipped input is distinct from quiet input")
    expect(AudioSignal.classify(rms: 0, peak: 0, received: false) == .noInput, "no buffers are distinct from silence")
    var feedback = ListeningFeedback()
    expect(feedback.update(.quiet, at: 10) == .active, "a short pause keeps the Listening label")
    expect(feedback.update(.silent, at: 11.99) == .active, "quiet and silence share one two-second buffer")
    expect(feedback.update(.quiet, at: 12) == .quiet, "sustained quiet shows a warning")
    expect(feedback.update(.active, at: 12.2) == .active, "voice immediately clears the warning")
    expect(feedback.update(.quiet, at: 12.4) == .active, "each pause gets a fresh buffer")
    expect(feedback.update(.clipped, at: 12.5) == .clipped, "clipping is reported immediately")
    expect(RuleCleanup().apply("  iPhone comma one  ", context: TextContext(mode: .exact)) == "  iPhone comma one  ", "exact mode preserves bytes")
    expect(RuleCleanup().apply("spell A B hyphen zero zero seven", context: TextContext(mode: .exact)) == "AB-007", "explicit spelling preserves leading zeros")
    expect(RuleCleanup().apply("spell three dot fourteen dot two", context: TextContext(mode: .exact)) == "3.14.2", "explicit spelling supports versions")
    expect(RuleCleanup().apply("spell the answer", context: TextContext(mode: .exact)) == "spell the answer", "ambiguous spelling stays literal")
    expect(RuleCleanup().apply("hello world", context: TextContext(application: "com.apple.Terminal", mode: .dictate)) == "Hello world.", "explicit prose mode overrides app inference")
    let migrated = try? JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    expect(migrated?.dictationMode == .automatic, "legacy exact-code preference migrates safely")
    var session = SessionGate()
    let capture = session.prepare()
    expect(session.phase == .starting && !session.canStart, "preparing is distinct from microphone readiness")
    expect(session.transition(.listening, session: capture), "first microphone samples mark listening")
    expect(session.transition(.processing, session: capture) && !session.canStart, "processing cannot be silently superseded")
    session.cancel()
    expect(session.canStart && !session.transition(.listening, session: capture), "late readiness cannot restart cancelled capture")
    let screen = CGRect(x: -1440, y: -300, width: 1440, height: 900)
    let placed = IndicatorLayout.frame(in: screen, size: CGSize(width: 376, height: 78), anchor: CGPoint(x: 20, y: -20))
    expect(screen.contains(placed), "indicator clamps invalid anchor on a negative-origin display")
    let defaultFrame = IndicatorLayout.frame(in: screen, size: CGSize(width: 376, height: 78))
    expect(defaultFrame.maxX == screen.maxX - 12 && defaultFrame.maxY == screen.maxY - 12,
           "the recording indicator defaults to the top right")
    let narrow = CGRect(x: 0, y: 0, width: 320, height: 200)
    expect(narrow.contains(IndicatorLayout.frame(in: narrow, size: CGSize(width: 376, height: 78))), "indicator fits a small visible display")
    let cases: [(String, String)] = [
        ("Meet at 3. Actually make that 4.", "Meet at 4."),
        ("Schedule our meeting at 5.15 p.m. Actually make that 5.50 p.m.", "Schedule our meeting at 5:50 PM."),
        ("Schedule the meeting at 5.15pm Actually make that 5.50pm", "Schedule the meeting at 5:50 PM."),
        ("Meet at 5.15pm, not 5.50pm.", "Meet at 5.15pm, not 5.50pm."),
        ("The discount is 7.05%.Keep invoice AB-007 separate from AB-070.", "The discount is 7.05%. Keep invoice AB-007 separate from AB-070."),
        ("iPhone and macOS use OAuth.", "iPhone and macOS use OAuth."),
        (#""iPhone" is a product name."#, #""iPhone" is a product name."#),
        (#"He said "do not change i into I"."#, #"He said "do not change i into I"."#),
        ("The article says, scratch that, as an example of a command.", "The article says, scratch that, as an example of a command."),
        ("The first shipment arrived before the second one.", "The first shipment arrived before the second one."),
        ("Well, I disagree.", "Well, I disagree."),
        ("Jordan actually agreed with the original proposal.", "Jordan actually agreed with the original proposal."),
        ("The comma key is broken and the words press enter belong in the instructions.", "The comma key is broken and the words press enter belong in the instructions."),
        ("Meet at 5.15 p.m., not 5.50 p.m.", "Meet at 5.15 p.m., not 5.50 p.m."),
        ("Keep AB-007, AB-070, -12.50, 7.05%, 3.14.2 and sam@example.com.", "Keep AB-007, AB-070, -12.50, 7.05%, 3.14.2 and sam@example.com."),
        (#"He said “new line, one hundred and five, iPhone”."#, #"He said “new line, one hundred and five, iPhone”."#)
    ]
    for (input, expected) in cases {
        let actual = RuleCleanup().apply(input)
        expect(actual == expected, "polish fidelity: \(input) -> \(actual)")
        expect(RuleCleanup().apply(actual) == actual, "cleanup is idempotent: \(input)")
    }
    let dictionary = TextContext(dictionary: ["eBay", "iPhone", "PostgreSQL"])
    expect(RuleCleanup().apply("ebay works with PostgreSQL.", context: dictionary) == "eBay works with PostgreSQL.", "configured spelling survives sentence capitalization")
}

func mixedAudioEvidenceChecks() {
    func evidence(_ confidence: [Double]) -> SpeechEvidence {
        var value = SpeechEvidence()
        for (index, score) in confidence.enumerated() {
            let start = Double(index) * 0.25
            value.observe(start: start, end: start + 0.5, confidence: score)
        }
        value.complete()
        return value
    }
    let speech = Array(repeating: 0.95, count: 24)
    let noise = Array(repeating: 0.4, count: 240)
    for scores in [speech + noise, noise + speech, speech + noise + speech] {
        expect(!evidence(scores).allowsAutomaticDelivery, "long mixed audio remains review-only regardless of speech position")
    }
    let softerSpeech = [0.83, 0.76, 0.77, 0.79, 0.78, 0.78]
    expect(!evidence(softerSpeech).allowsAutomaticDelivery && evidence(softerSpeech).allowsHeldDictationDelivery,
           "deliberate hold accepts supported soft speech without relaxing toggle dictation")
    expect(!evidence(Array(repeating: 0.77, count: 12)).allowsHeldDictationDelivery,
           "moderate confidence alone cannot authorize held dictation")
    expect(!evidence([0.83, 0.4, 0.78, 0.76]).allowsHeldDictationDelivery,
           "strong and moderate speech must share an adjacent pair")
    for scores in [noise, softerSpeech + noise, noise + softerSpeech, softerSpeech + noise + softerSpeech] {
        expect(!evidence(scores).allowsHeldDictationDelivery, "noise and long mixed audio still require review for held dictation")
    }
    expect(!evidence([0.99]).allowsHeldDictationDelivery, "an isolated positive window still requires review")
    var failedHeld = evidence(softerSpeech); failedHeld.fail()
    expect(!failedHeld.allowsHeldDictationDelivery, "failed analysis cannot authorize held dictation")
    let repeatedBursts = (0..<20).flatMap { _ in [0.95, 0.95] + Array(repeating: 0.4, count: 9) }
    expect(!evidence(repeatedBursts).allowsAutomaticDelivery, "short positive bursts cannot authorize a mostly uncertain clip")
    expect(!evidence(repeatedBursts).allowsHeldDictationDelivery,
           "push-to-dictate still rejects mostly uncertain audio")
    // Observed push-to-dictate regression: 13 seconds with five qualified
    // seconds spread across the clip and no gap longer than three seconds.
    let pacedSpeech = Array(repeating: 0.9, count: 6)
    let pause = Array(repeating: 0.2, count: 11)
    let paced = pacedSpeech + pause + pacedSpeech + pause
        + Array(repeating: 0.9, count: 5) + Array(repeating: 0.2, count: 12)
    expect(evidence(paced).allowsHeldDictationDelivery, "explicit hold permits distributed speech with ordinary pauses")
    expect(!evidence(paced).allowsAutomaticDelivery, "toggle and editing keep the stricter pause allowance")
    expect(!evidence(paced + [0.2]).allowsHeldDictationDelivery, "a longer final gap still blocks held delivery")
    let sparse = Array(repeating: 0.2, count: 2) + Array(paced.dropFirst(2))
    expect(!evidence(sparse).allowsHeldDictationDelivery, "too little total speech still blocks held delivery")
    expect(evidence(speech + Array(repeating: 0.2, count: 6)).allowsAutomaticDelivery, "ordinary trailing pause keeps normal speech automatic")
    expect(evidence(speech + Array(repeating: 0.2, count: 6) + speech).allowsAutomaticDelivery, "ordinary internal pause keeps sustained speech automatic")
    expect(!evidence(speech + Array(repeating: 0.2, count: 20)).allowsAutomaticDelivery, "long held silent pause needs review too")
    expect(!evidence(Array(repeating: 0.5, count: 20)).allowsAutomaticDelivery, "quiet uncertain speech is preserved for review")
    expect(!evidence([0.95]).allowsAutomaticDelivery, "short isolated speech retains conservative review behavior")
    expect(evidence(speech + Array(repeating: 0.4, count: 12)).allowsAutomaticDelivery, "three-second trailing gap is the documented boundary")
    expect(!evidence(speech + Array(repeating: 0.4, count: 13)).allowsAutomaticDelivery, "trailing gap beyond the boundary requires review")
    expect(evidence(Array(repeating: 0.4, count: 12) + speech).allowsAutomaticDelivery, "three-second leading gap is counted once")
    expect(!evidence(Array(repeating: 0.4, count: 13) + speech).allowsAutomaticDelivery, "leading gap beyond the boundary requires review")
    expect(!evidence(speech + Array(repeating: 0.4, count: 14) + speech).allowsAutomaticDelivery, "later speech cannot erase a closed internal gap")
    let overlapping = evidence([0.95, 0.95, 0.95])
    expect(overlapping.speechSeconds == 1, "overlapping windows count as one second of qualified audio")
    expect(overlapping.unqualifiedSeconds == 0 && overlapping.longestUnqualifiedSpan == 0, "continuous speech has no unqualified gaps")
    var missingTail = SpeechEvidence()
    missingTail.observe(start: 0, end: 0.5, confidence: 0.95)
    missingTail.observe(start: 0.25, end: 0.75, confidence: 0.95)
    var partialHop = missingTail
    partialHop.complete(duration: 0.9)
    expect(partialHop.allowsAutomaticDelivery && abs(partialHop.unqualifiedSeconds - 0.15) < 0.0001, "small unclassified tail counts as unqualified audio")
    missingTail.complete(duration: 10)
    expect(!missingTail.allowsAutomaticDelivery, "missing final classifier coverage fails closed")
}

func structuredCorrectionChecks() {
    for (raw, expected) in [("hello (world)", "Hello (world)."), ("hello: this is ready", "Hello: this is ready."), ("hello — i agree", "Hello — I agree."), ("hello (AB123)", "Hello (AB123)."), ("hello:123", "Hello:123."), ("hello — 123", "Hello — 123."), ("i agree (i think)", "I agree (I think)."), ("hello [world]", "Hello [world]."), ("pay ₹1,205", "Pay ₹1,205."), ("pay $10", "Pay $10."), ("hello + world", "Hello + world."), ("i + me", "I + me."), ("hello / world", "Hello / world.")] {
        let cleaned = RuleCleanup().apply(raw)
        expect(cleaned == expected && RuleCleanup().apply(cleaned) == cleaned, "prose formatting is distinct from ID protection: \(raw)")
    }
    for mark in [":", "·", "|", "⇄", "⊕", "※", "🧩", "👩🏽‍💻", "\u{200B}", "\u{2060}", "/", "\\", "_", "-", ".", ",", "=", "@"] {
        for space in [" ", "\u{00A0}", "\u{202F}", "\t"] {
            for (old, new) in [("123\(space)\(mark)\(space)456", "789"), ("123", "456\(space)\(mark)\(space)789")] {
                let input = "Reference \(old) actually make that \(new)."
                expect(DictationLanguage.corrections(input) == input, "connected span refuses partial numeric operand: \(input)")
                let output = RuleCleanup().apply(input)
                expect(output.lowercased().contains("actually make that"), "pipeline keeps ambiguous compound correction visible")
                expect(RuleCleanup().apply(output) == output, "connected spans remain stable after punctuation cleanup")
            }
        }
        for input in ["Meet Monday actually make that Tuesday \(mark) ABC.", "Reference ABC \(mark) Monday actually make that Tuesday.", "Work with Jordan actually make that Priya \(mark) 007.", "Send 123 \(mark) 456 invoices, sorry, 789 invoices.", "Meet at 123 \(mark) 5:15 PM actually make that 5:50 PM."] {
            expect(DictationLanguage.corrections(input) == input, "all correction branches obey connected-span boundaries: \(input)")
            let cleaned = RuleCleanup().apply(input)
            expect(cleaned == input && RuleCleanup().apply(cleaned) == cleaned, "all branches preserve connected spans through formatting")
        }
    }
    for (input, output) in [("Pay -3.25 actually make that +4.75.", "Pay +4.75."), ("The rate is 3% actually make that 4% tomorrow.", "The rate is 4% tomorrow."), ("The value is 3 actually make that 4. Next comes delivery.", "The value is 4. Next comes delivery."), ("Work with Jordan actually make that Priya, and send it.", "Work with Priya, and send it.")] {
        expect(RuleCleanup().apply(input) == output, "supported prose punctuation and operand decorations: \(input)")
    }
    for space in [" ", "\u{00A0}", "\u{202F}", "\t"] {
        for (old, new) in [("1" + space + "205", "2" + space + "500"), ("1205", "2" + space + "500"), ("1" + space + "205", "2500")] {
            for gap in [" ", ". "] {
                let input = "Pay \(old)\(gap)actually make that \(new)."
                expect(DictationLanguage.corrections(input) == input, "spaced amounts never partially rewritten")
                let output = RuleCleanup().apply(input)
                expect(output.lowercased().contains("actually make that") && RuleCleanup().apply(output) == output, "ambiguous grouped amount stays visible and stable")
            }
        }
        let repeated = "Send 1\(space)205 invoices, sorry, 500 invoices."
        expect(DictationLanguage.corrections(repeated) == repeated, "repeated-unit correction consumes complete grouped amount or preserves it")
    }
    for input in ["Reference ABC-Monday actually make that Tuesday.", "Reference Monday/Tuesday actually make that Wednesday.", "Meet Monday actually make that Tuesday-01.", "Reference 123 / 456 actually make that 789.", "Reference 123 actually make that 456 / 789.", "Work with AB-Jordan actually make that Priya."] {
        expect(RuleCleanup().apply(input) == input, "complete nonnumeric/space-separated operands: \(input)")
    }
    expect(RuleCleanup().apply("Meet Monday actually make that Tuesday.") == "Meet Tuesday.", "standalone weekday correction remains supported")
    expect(RuleCleanup().apply("Work with Jordan actually make that Priya.") == "Work with Priya.", "standalone name correction remains supported")
    let preserved = [
        "Reference 123/456 actually make that 789.",
        "Date 12/11/2026 actually make that 2027.",
        "Date 12/11/2026. Actually make that 2027.",
        "The value is 3. Actually make that 4-AB.",
        "Reference 123-456 actually make that 789.",
        "Reference 123_456 actually make that 789.",
        "Reference AB007 actually make that 070.",
        "Reference AB-007 actually make that AB-070.",
        "Reference 123\\456 actually make that 789.",
        "Reference 123·456 actually make that 789.",
        "Version 3.14.2 actually make that 4.0.1.",
        "Version 3.14.2. Actually make that 4.",
        "The value is 3 actually make that 4/789.",
        "The value is 3 actually make that 4.0.1.",
        "The value is 3 actually make that 4_AB.",
        "The value is 3 actually make that 4–AB.",
        "The value is 3 actually make that 4@AB.",
        "The value is 3 actually make that 4#AB.",
        "The value is 3 actually make that 4:AB.",
        "The value is 3 actually make that 4,AB.",
        "The value is 3 actually make that 4.00USD.",
        "The value is $3 actually make that 4.",
        "The value is 3 actually make that 4%.",
        "Reference 123/456 invoices, sorry, 789 invoices.",
        "Reference 123/5.15 p.m. Actually make that 5.50 p.m.",
        "Meet at 5.15 p.m. Actually make that 5.50 p.m./AB.",
        "Do not actually make that payment."
    ]
    for input in preserved {
        expect(DictationLanguage.corrections(input) == input, "whole correction operands: \(input)")
        let baseline = RuleCleanup().apply(input)
        expect(baseline == input, "rule pipeline preserves ambiguous correction: \(input) -> \(baseline)")
        expect(RuleCleanup().apply(baseline) == baseline, "ambiguous correction remains safe on repeated cleanup")
        expect(RuleCleanup().apply(input, context: TextContext(mode: .exact)) == input, "exact mode preserves correction: \(input)")
        expect(!CleanupFidelity.accepts("Changed value.", baseline: baseline, dictionary: []), "optional cleanup cannot rewrite preserved operands")
    }
    // Both original and replacement must be complete values, across the same
    // sentence and ASR-inserted sentence boundaries. Test unknown separators too.
    for separator in ["/", "\\", "-", "_", ".", ":", "@", "#", "·", "–", "=", "+", "％"] {
        for gap in [" ", ". "] {
            for (old, new) in [("123" + separator + "456" + (separator == "." ? ".7" : ""), "789"), ("123", "789" + separator + "ABC")] {
                let input = "Reference \(old)\(gap)actually make that \(new)."
                expect(DictationLanguage.corrections(input) == input, "complete operand boundary matrix: \(input)")
            }
        }
    }
    let corrected = [
        ("The value is 3 actually make that 4.", "The value is 4."),
        ("The value is 3. Actually make that 4.", "The value is 4."),
        ("The value is 3.25. Actually make that 4.75.", "The value is 4.75."),
        ("Pay 1,205 actually make that 12,500.", "Pay 12,500."),
        ("The value is -3.25 actually make that +4.75.", "The value is +4.75."),
        ("The discount is 7.05% actually make that 8.5%.", "The discount is 8.5%."),
        ("Choose 3rd actually make that 4th.", "Choose 4th."),
        ("Meet at 5:15 actually make that 5:50.", "Meet at 5:50."),
        ("Meet at 5.15 p.m. Actually make that 5.50 p.m.", "Meet at 5:50 PM."),
        ("Send 1,500 invoices, sorry, 2,500 invoices.", "Send 2,500 invoices."),
        ("The value is 3, sorry make that 4, and keep going.", "The value is 4, and keep going.")
    ]
    for (input, output) in corrected {
        expect(DictationLanguage.corrections(input) == output, "complete numeric correction: \(input)")
        expect(RuleCleanup().apply(input) == output, "complete numeric correction through pipeline: \(input)")
        expect(RuleCleanup().apply(output) == output, "corrected numeric output is idempotent")
    }
}
