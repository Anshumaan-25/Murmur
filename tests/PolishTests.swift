import Foundation
import MurmurCore

func polishProtocolChecks() async {
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
