import Foundation
import MurmurCore

func polishProtocolChecks() async {
    let structured = "Reference 123/456 actually make that 789."
    let optional = await SystemCleanup(budget: 0.01).attempt(structured, context: TextContext())
    expect(optional.text == structured, "optional cleanup provider preserves ambiguous structured correction")
    expect(!CleanupFidelity.accepts("Reference 123/789.", baseline: structured, dictionary: []), "optional model gate rejects the original composite-ID regression")
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
    structuredCorrectionChecks()
    let mediaDefaults = try? JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    expect(mediaDefaults?.pauseMedia == true, "media pause defaults on for existing preferences")
    var mediaDisabled = Preferences(); mediaDisabled.pauseMedia = false
    let mediaRoundTrip = try? JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(mediaDisabled))
    expect(mediaRoundTrip?.pauseMedia == false, "media pause opt out survives saving")

    var activity = SpeechActivity()
    for i in 0..<100 { _ = activity.observe(rms: 0.0005, uptime: Double(i) * 0.04) }
    expect(activity.lastVoice == nil, "stationary low noise is not speech")
    for i in 100..<125 { _ = activity.observe(rms: 0.003, uptime: Double(i) * 0.04) }
    let lastVoice = activity.lastVoice
    for i in 125..<225 { _ = activity.observe(rms: 0.0005, uptime: Double(i) * 0.04) }
    expect(lastVoice != nil && activity.lastVoice == lastVoice, "noise after speech allows silence completion")
    var loudNoise = SpeechActivity()
    for i in 0..<100 { _ = loudNoise.observe(rms: 0.02, uptime: Double(i) * 0.04) }
    expect(loudNoise.lastVoice == nil, "stationary noise present at start establishes a baseline")
    var quietActivity = SpeechActivity()
    for i in 0..<20 { _ = quietActivity.observe(rms: 0.0001, uptime: Double(i) * 0.04) }
    expect(quietActivity.observe(rms: 0.0017, uptime: 1), "quiet speech above baseline counts as activity")

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

func structuredCorrectionChecks() {
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
