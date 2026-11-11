import Foundation
import AppKit
import MurmurCore

var checks = 0
var failed = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { failed += 1; print("FAIL: \(name)") }
}
@main struct CoreVerification {
 @MainActor static func main() async {
polishTextChecks()
await polishProtocolChecks()
var gate = SessionGate()
let old = gate.begin(); gate.cancel()
expect(!gate.accepts(old), "cancel invalidates work")
let first = gate.begin(); let second = gate.begin()
expect(!gate.accepts(first), "new session supersedes old")
expect(gate.transition(.processing, session: second), "capture finishes")
expect(gate.transition(.inserting, session: second), "result may insert")
expect(gate.transition(.idle, session: second), "insertion ends")
expect(!gate.transition(.inserting, session: second), "duplicate insertion rejected")
let framed = AudioTools.frames(Array(repeating: Float(0.2), count: 1500))
expect(framed.map { $0.samples.count } == [640, 640, 220], "forty millisecond framing and tail")
expect(AudioTools.trimmed([AudioFrame(Array(repeating: 0, count: 640))]).isEmpty, "silence trimmed")
expect(abs(AudioFrame([0.5, -0.5]).rms - 0.5) < 0.0001, "level measurement")
expect(AudioTools.wav(framed).count == 3044, "PCM container size")
let board = NSPasteboard(name: NSPasteboard.Name("local.murmur.test." + UUID().uuidString))
let original = NSPasteboardItem(); original.setString("Clipboard fixture", forType: .string)
let binaryType = NSPasteboard.PasteboardType("local.murmur.binary")
original.setData(Data([0, 7, 128, 255]), forType: binaryType)
let secondItem = NSPasteboardItem(); secondItem.setString("Another item", forType: .string)
board.writeObjects([original, secondItem])
do {
    let saved = try PasteboardSnapshot(board)
    board.clearContents(); board.setString("Temporary text", forType: .string); saved.restore(board)
    expect(board.pasteboardItems?.count == 2, "all clipboard items restored")
    expect(board.pasteboardItems?.first?.data(forType: binaryType) == Data([0, 7, 128, 255]), "custom clipboard type preserved")
    expect(board.pasteboardItems?.last?.string(forType: .string) == "Another item", "second clipboard item preserved")
} catch { expect(false, "clipboard snapshot succeeds") }
board.releaseGlobally()
struct Golden: Decodable { let input: String; let expected: String }
let goldenURL = Bundle.module.url(forResource: "cases", withExtension: "json", subdirectory: "golden")!
do {
    let cases = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: goldenURL))
    expect(cases.count >= 30, "golden suite minimum")
    for (index, sample) in cases.enumerated() { let actual = RuleCleanup().apply(sample.input); if actual != sample.expected { print("Golden \(index): got \(actual.debugDescription), expected \(sample.expected.debugDescription)") }; expect(actual == sample.expected, "golden \(index)") }
} catch { expect(false, "golden fixtures decode") }
expect(RuleCleanup().apply(#"he said, "send it.""#) == #"He said, "send it.""#, "cleanup preserves punctuation inside a closing quote")
expect(RuleCleanup().apply("she asked, “is it ready?”") == "She asked, “is it ready?”", "quoted question does not receive a second period")
expect(RuleCleanup().apply("send fifteen invoices, sorry, fifty invoices to the office") == "Send 50 invoices to the office.", "explicit correction replaces a repeated quantity")
expect(RuleCleanup().apply("send 1,500 invoices, sorry, 2,500 invoices to the office") == "Send 2,500 invoices to the office.", "quantity correction preserves thousands separators")
expect(RuleCleanup().apply("send 15 invoices, sorry, 50 receipts are missing") == "Send 15 invoices, sorry, 50 receipts are missing.", "different items keep both quantities")
do {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("decoder-fixture")
    let script = #"""
    #!/bin/sh
    case " $* " in
      *" -nt "*) printf 'custom\ntranscript\n';;
      *) printf 'send 15 invoices, sorry, 50\n invoices to the office.\n';;
    esac
    """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let bundled = ExecutableSpeechProvider(executable: executable, model: executable)
    let result = try await bundled.transcribe(framed, language: "en-US", vocabulary: [])
    expect(result.text == "send 15 invoices, sorry, 50 invoices to the office.", "bundled decoding joins segment boundaries without exposing timestamps")
    expect(RuleCleanup().apply(result.text) == "Send 50 invoices to the office.", "explicit corrections survive decoder segment boundaries")
    let custom = ExecutableSpeechProvider(executable: executable, model: executable, timestampDecoding: false)
    let customResult = try await custom.transcribe(framed, language: "en-US", vocabulary: [])
    expect(customResult.text == "custom\ntranscript", "custom decoder retains its flags and line breaks")
} catch { expect(false, "executable speech provider fixture: \(error)") }
do {
    let sentinel = "fixture-secret-sentinel"
    setenv("HF_TOKEN", sentinel, 1)
    defer { unsetenv("HF_TOKEN") }
    let response = try await LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", #"printf '%s' "${HF_TOKEN-unset}""#], input: Data(), timeout: 2)
    expect(response == "unset", "decoder environment does not inherit credentials")
    do {
        _ = try await LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "/bin/sleep 2 & exit 0"], input: Data(), timeout: 0.15)
        expect(false, "child retaining stdout cannot make a deadline succeed")
    } catch { expect(error.localizedDescription.contains("timed out"), "child retaining stdout has a terminal deadline") }
    do {
        _ = try await LocalProcess.run(executable: URL(fileURLWithPath: "/bin/dd"), arguments: ["if=/dev/zero", "bs=1048576", "count=2"], input: Data(), timeout: 3)
        expect(false, "oversized decoder output rejected")
    } catch { expect(error.localizedDescription.contains("exceeded"), "decoder output is bounded") }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("fixture decoder")
    try Data("#!/bin/sh\nprintf approved".utf8).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    let approval = try DecoderApproval(executable: path)
    let valid = try await LocalProcess.run(executable: path, arguments: [], input: Data(), timeout: 2, approval: approval)
    expect(valid == "approved", "approved bytes execute from a private staged copy")
    try Data("#!/bin/sh\nprintf substituted".utf8).write(to: path)
    do {
        _ = try await LocalProcess.run(executable: path, arguments: [], input: Data(), timeout: 2, approval: approval)
        expect(false, "replaced custom decoder must require approval")
    } catch { expect(error.localizedDescription.contains("changed"), "changed custom bytes fail closed") }
} catch { expect(false, "decoder boundary fixtures: \(error)") }
do {
    let store = try HistoryStore(path: ":memory:")
    let record = Utterance(application: "test", duration: 4, raw: "um hello", cleaned: "Hello.", inserted: "Hello.", outcome: "inserted", latency: 0.5)
    try store.save(record)
    let savedRows = try store.records(); expect(savedRows.first?.raw == "um hello", "raw history preserved")
    let searched = try store.records(search: "Hello"); expect(searched.count == 1, "history searchable")
    try store.save(Utterance(timestamp: Date().addingTimeInterval(-90000), application: "test", duration: 1, raw: "old", cleaned: "Old.", inserted: "", outcome: "copied", latency: 0.2))
    try store.prune(.day); let recentRows = try store.records(); expect(recentRows.count == 1, "daily retention expires old rows")
    try store.prune(.never); let emptyRows = try store.records(); expect(emptyRows.isEmpty, "disabled history removes content")
} catch { expect(false, "history integration") }
do {
    let store = try HistoryStore(path: ":memory:")
    try store.setDictionary(["Murmur", "Acme", "Acme", " "])
    let vocabulary = try store.dictionary()
    expect(vocabulary == ["Acme", "Murmur"], "dictionary canonical and deduplicated")
    let context = TextContext(dictionary: vocabulary, expansions: ["my signature": "Regards,\nAlex"])
    expect(RuleCleanup().apply("try murmur", context: context) == "Try Murmur.", "dictionary spelling retained")
    expect(RuleCleanup().apply("My signature.", context: context) == "Regards,\nAlex", "exact spoken expansion")
    expect(RuleCleanup().apply("change my signature please", context: context) == "Change my signature please.", "embedded trigger not expanded")
    try store.setValues(["my signature": "Regards, Alex"], table: "expansions")
    let loaded = try store.values(table: "expansions")
    expect(loaded["my signature"] == "Regards, Alex", "expansion persists")
} catch { expect(false, "vocabulary integration") }
expect(RuleCleanup().apply("i can't attend", context: TextContext(style: .formal)) == "I cannot attend.", "formal style expands contraction")
expect(RuleCleanup().apply("regarding tomorrow", context: TextContext(style: .casual)) == "About tomorrow.", "casual style stays conservative")
expect(RuleCleanup().apply("i can't attend") == "I can't attend.", "neutral preserves wording")
do {
    let store = try HistoryStore(path: ":memory:")
    try store.setValues(["local.test.mail": "formal", "local.test.chat": "casual"], table: "app_styles")
    let values = try store.values(table: "app_styles")
    expect(values["local.test.mail"] == "formal", "style keyed by destination")
    try store.setValues([:], table: "app_styles")
    let empty = try store.values(table: "app_styles")
    expect(empty.isEmpty, "style removal")
} catch { expect(false, "style storage") }
expect(!RecordingPolicy.shouldFinish(duration: 5, silence: 5, heardSpeech: false, handsFree: true, silenceLimit: 1, maximum: 120), "hands-free waits for first speech")
do {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordings = directory.appendingPathComponent("Recordings")
    try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recordings.path)
    try PrivateStorage.directory(directory)
    let database = directory.appendingPathComponent("history.sqlite")
    let store = try HistoryStore(path: database.path)
    func mode(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }
    let supportMode = try mode(directory)
    let databaseMode = try mode(database)
    expect(supportMode == 0o700 && databaseMode == 0o600, "legacy support mode repaired and database created private")
    let record = Utterance(application: "fixture", duration: 1, raw: "synthetic", cleaned: "Synthetic.", inserted: "", outcome: "available", latency: 0)
    try store.save(record)
    try store.saveRecording(Data([0, 1, 2]), for: record.id)
    let audio = recordings.appendingPathComponent(record.id.uuidString + ".wav")
    let audioMode = try mode(audio)
    let recordingMode = try mode(recordings)
    expect(audioMode == 0o600 && recordingMode == 0o700, "retained WAV and recording directory are private")
    let orphan = recordings.appendingPathComponent(UUID().uuidString + ".wav")
    try Data([1]).write(to: orphan)
    try store.prune(.forever)
    expect(!FileManager.default.fileExists(atPath: orphan.path), "startup-style reconciliation removes legacy orphans even with forever retention")
    guard chflags(audio.path, UInt32(UF_IMMUTABLE)) == 0 else { throw POSIXError(.EIO) }
    defer { _ = chflags(audio.path, 0) }
    do {
        try store.delete(record.id)
        expect(false, "failed WAV deletion must preserve its row")
    } catch {
        let hasRecord = try store.contains(record.id)
        expect(hasRecord, "failed WAV deletion leaves the record available for retry")
    }
    _ = chflags(audio.path, 0)
    try store.save(record, retention: .never)
    let stillPresent = try store.contains(record.id)
    expect(stillPresent, "never-save suppresses a write without purging from the save path")
    try store.prune(.never)
    try store.save(record, retention: .never)
    let afterOptOut = try store.contains(record.id)
    expect(!afterOptOut && !FileManager.default.fileExists(atPath: audio.path), "current opt-out blocks repopulation and prunes audio")
    let link = directory.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: recordings)
    do { try PrivateStorage.directory(link); expect(false, "private storage refuses symlink directories") }
    catch { expect(true, "private storage rejects a symlink directory") }
} catch { expect(false, "retention and private storage fixtures: \(error)") }
expect(RecordingPolicy.sampleLimit(seconds: 5) == 80000 && RecordingPolicy.sampleLimit(seconds: .infinity) == 1920000, "capture sample cap is independent of timer delivery")
expect(RecordingPolicy.shouldFinish(duration: 5, silence: 2, heardSpeech: true, handsFree: true, silenceLimit: 1.5, maximum: 120), "hands-free ends on silence")
expect(!RecordingPolicy.shouldFinish(duration: 5, silence: 2, heardSpeech: true, handsFree: false, silenceLimit: 1.5, maximum: 120), "toggle ignores silence")
expect(RecordingPolicy.shouldFinish(duration: 120, silence: 0, heardSpeech: false, handsFree: false, silenceLimit: 1.5, maximum: 120), "duration cap always enforced")
expect(!RecordingPolicy.shouldFinish(duration: 5, silence: 2, heardSpeech: true, handsFree: true, silenceLimit: 1.5, maximum: 120, holdToTalk: true), "hold-to-talk ignores hands-free silence")
expect(RecordingPolicy.shouldFinish(duration: 120, silence: 0, heardSpeech: false, handsFree: true, silenceLimit: 1.5, maximum: 120, holdToTalk: true), "hold-to-talk still honors the duration cap")
let cancellationBegan = Date()
let cancelledProcess = Task { try await LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], input: Data(), timeout: 15) }
try? await Task.sleep(nanoseconds: 60_000_000)
cancelledProcess.cancel()
do { _ = try await cancelledProcess.value; expect(false, "cancel stops child process") } catch { expect(Date().timeIntervalSince(cancellationBegan) < 2, "cancel stops child promptly") }
do {
    let caps = try EditingCommand.apply("uppercase", selected: "Hello"); expect(caps == "HELLO", "uppercase editing")
    let lower = try EditingCommand.apply("lowercase", selected: "Hello"); expect(lower == "hello", "lowercase editing")
    let shorter = try EditingCommand.apply("make this shorter", selected: "I wanted to let you know that we really need this in order to finish."); expect(shorter == "We need this to finish.", "shorter command preserves key facts")
    let edited = try await CommandRewrite().rewrite(instruction: "make formal", selected: "I can't attend.")
    expect(edited == .replacement("I cannot attend."), "local editing without model")
} catch { expect(false, "known editing commands") }
do { _ = try await CommandRewrite().rewrite(instruction: "Invent a different story", selected: "Keep this fact."); expect(false, "unsupported instruction rejected without a model") } catch { expect(true, "unsupported editing is explicit") }
let ownerBoard = NSPasteboard(name: .init("local.murmur.owner." + UUID().uuidString))
ownerBoard.setString("Original", forType: .string)
do {
    let snapshot = try PasteboardSnapshot(ownerBoard)
    ownerBoard.clearContents(); ownerBoard.setString("Offered text", forType: .string)
    let generation = ownerBoard.changeCount
    ownerBoard.clearContents(); ownerBoard.setString("New user copy", forType: .string)
    expect(!snapshot.restore(ownerBoard, ifUnchangedSince: generation), "new clipboard owner protected")
    expect(ownerBoard.string(forType: .string) == "New user copy", "new user copy remains intact")
} catch { expect(false, "clipboard ownership check") }
ownerBoard.releaseGlobally()
let yesterday = Date().addingTimeInterval(-86400)
let usage = UsageStatistics([Utterance(application: "test", duration: 6, raw: "", cleaned: "Hello world", inserted: "", outcome: "copied", latency: 0.1), Utterance(timestamp: yesterday, application: "test", duration: 6, raw: "", cleaned: "Another sentence", inserted: "", outcome: "copied", latency: 0.1)])
expect(usage.words == 4, "statistics count all words")
expect(abs(usage.wordsPerMinute - 20) < 0.01, "statistics use recording duration")
expect(usage.streak == 2, "statistics count consecutive local days")

var hold = HoldGesture()
expect(hold.change(to: true) == true, "hold starts once")
expect(hold.change(to: true) == nil, "hold key repeat ignored")
expect(hold.change(to: false) == false, "hold releases once")
expect(hold.change(to: false) == nil, "orphan hold release ignored")
expect(!hold.reset(), "idle hold reset")
_ = hold.change(to: true); expect(hold.reset(), "reconfiguration releases a held gesture")
expect(Set(HoldKey.allCases.map(\.code)).count == HoldKey.allCases.count, "physical hold keys are distinct")
do {
    let oldSettings = Data(#"{"language":"en-GB","clipboardDelay":0.7,"holdEnabled":false}"#.utf8)
    let loaded = try JSONDecoder().decode(Preferences.self, from: oldSettings)
    expect(loaded.language == "en-GB" && loaded.clipboardDelay == 0.7 && !loaded.holdEnabled, "old settings preserved during migration")
    expect(loaded.holdKey == .globe && loaded.speechEngine == .automatic && loaded.preserveCode, "new preferences default safely")
    expect(loaded.appearance == .system, "older preferences follow system appearance")
    var dark = loaded
    dark.appearance = .dark
    let roundTrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(dark))
    expect(roundTrip.appearance == .dark && roundTrip.language == loaded.language, "appearance override round-trips with existing settings")
    let invalid = try JSONDecoder().decode(Preferences.self, from: Data(#"{"language":"en-IN","holdKey":"futureKey","maximumSeconds":-1,"appearance":"futureTheme"}"#.utf8))
    expect(invalid.appearance == .system, "unknown appearance falls back to system")
    expect(invalid.language == "en-IN" && invalid.holdKey == .globe && invalid.maximumSeconds == 5, "unknown key does not reset other preferences")
} catch { expect(false, "preference migration decodes") }
expect(ApplicationCategory.classify(bundle: "com.apple.Terminal") == .terminal, "terminal category")
expect(ApplicationCategory.classify(bundle: "com.microsoft.VSCode") == .code, "editor category")
expect(ApplicationCategory.classify(bundle: "com.apple.mail") == .email, "email category")
expect(ApplicationCategory.classify(bundle: "com.apple.Safari") == .browser, "browser category")
expect(ApplicationCategory.classify(bundle: "unknown") == .other, "unknown category is conservative")
expect(ApplicationCategory.classify(bundle: "unknown", declaredCategory: "public.app-category.developer-tools") == .code, "declared category fallback")
expect(RuleCleanup().apply("git status", context: TextContext(application: "com.apple.Terminal")) == "git status", "terminal syntax preserved")
expect(RuleCleanup().apply("let value = 3.2", context: TextContext(application: "com.microsoft.VSCode")) == "let value = 3.2", "code syntax preserved")
expect(RuleCleanup().apply("hello there", context: TextContext(application: "com.apple.Terminal", preserveCode: false)) == "Hello there.", "code preservation can be disabled")
expect(!CleanupFidelity.accepts("Hello.", baseline: "Hello world.", dictionary: []), "model cannot drop content words")
expect(!CleanupFidelity.accepts("Here is a joke.", baseline: "Tell me a joke.", dictionary: []), "model cannot answer dictation")
expect(CleanupFidelity.accepts("We arrived.", baseline: "we arrived.", dictionary: []), "model can safely capitalize an ordinary sentence opener")
expect(!CleanupFidelity.accepts("Try acme.", baseline: "Try Acme.", dictionary: ["Acme"]), "model must preserve dictionary spelling")
let timerBegan = Date()
do { _ = try await Deadline.run(seconds: 0.03) { try await Task.sleep(nanoseconds: 2_000_000_000); return "late" }; expect(false, "deadline rejects slow work") }
catch { expect(Date().timeIntervalSince(timerBegan) < 0.5, "deadline returns promptly") }
do { let answer = try await Deadline.run(seconds: 1) { 42 }; expect(answer == 42, "deadline returns fast work") }
catch { expect(false, "deadline fast work succeeds") }
let deadlineTask = Task { try await Deadline.run(seconds: 10) { try await Task.sleep(nanoseconds: 10_000_000_000); return 7 } }
deadlineTask.cancel()
do { _ = try await deadlineTask.value; expect(false, "deadline propagates caller cancellation") } catch { expect(true, "deadline propagates caller cancellation") }
expect(!CleanupFidelity.accepts("Do not, approve send back.", baseline: "Do not approve, send back.", dictionary: []), "model cannot move punctuation between words")
expect(!CleanupFidelity.accepts("Dose is 5 mg.", baseline: "Dose is -5 mg.", dictionary: []), "model cannot remove a sign")
expect(!CleanupFidelity.accepts("The fee is €25.", baseline: "The fee is $25.", dictionary: []), "model cannot change currency")
expect(!CleanupFidelity.accepts("Use ID ABC 12.", baseline: "Use ID AbC-12.", dictionary: []), "model cannot change an identifier")
expect(!CleanupFidelity.accepts("Great.", baseline: "Great!", dictionary: []), "explicit punctuation retained")
expect(CleanupQualification(cases: 90, passed: 90, accepted: 70, p95Seconds: 0.5).eligible, "model eligibility requires quality and speed")
expect(!CleanupQualification(cases: 90, passed: 89, accepted: 70, p95Seconds: 0.5).eligible, "one failed golden blocks model eligibility")
expect(!CleanupQualification(cases: 90, passed: 90, accepted: 70, p95Seconds: 1.1).eligible, "slow model cannot qualify")
expect(!CleanupQualification(cases: 90, passed: 90, accepted: 0, p95Seconds: 0.1).eligible, "all-fallback benchmark cannot qualify a model")
let digestCases = [CleanupFixture(input: "hello", expected: "Hello.")]
expect(CleanupFixture.fingerprint(digestCases) == CleanupFixture.fingerprint(digestCases), "fixture fingerprint is stable")
expect(CleanupFixture.fingerprint(digestCases) != CleanupFixture.fingerprint([CleanupFixture(input: "hello", expected: "Hello!")]), "changed expectations invalidate qualification")
var metrics = SessionMeasurements()
metrics.feedback(trigger: 1, painted: 1.05); metrics.feedback(trigger: 5, painted: 4)
metrics.insertion(released: 2, finished: 2.8)
expect(metrics.feedbackMilliseconds.count == 1, "invalid clock samples ignored")
expect(abs((SessionMeasurements.median(metrics.feedbackMilliseconds) ?? 0) - 50) < 0.1, "feedback metric uses event clock")
expect(abs((SessionMeasurements.median(metrics.insertionMilliseconds) ?? 0) - 800) < 0.1, "insertion metric covers release to completion")
let deliveryBoard = NSPasteboard(name: .init("local.murmur.transaction." + UUID().uuidString))
deliveryBoard.setString("Prior", forType: .string)
let transaction = ClipboardDelivery()
do {
    var observed = ""
    try await transaction.deliver("Delivered", board: deliveryBoard, delay: 0.01) { observed = deliveryBoard.string(forType: .string) ?? "" }
    do {
        try await transaction.deliver("Should not publish", board: deliveryBoard, delay: 0.01, validate: {
            deliveryBoard.clearContents()
            deliveryBoard.setString("New owner", forType: .string)
        }) { expect(false, "clipboard change must prevent posting") }
        expect(false, "clipboard change must block publication")
    } catch is ClipboardDelivery.Changed {
        expect(deliveryBoard.string(forType: .string) == "New owner", "clipboard change during validation preserves new owner")
    }
    var validationCalls = 0
    do {
        try await transaction.deliver("Published then superseded", board: deliveryBoard, delay: 0.01, validate: {
            validationCalls += 1
            if validationCalls == 2 {
                deliveryBoard.clearContents()
                deliveryBoard.setString("New owner before posting", forType: .string)
            }
        }) { expect(false, "clipboard generation must be rechecked after the last destination check") }
        expect(false, "lost clipboard offer must block paste")
    } catch is ClipboardDelivery.Changed {
        expect(deliveryBoard.string(forType: .string) == "New owner before posting", "new owner survives lost offer")
    }
    deliveryBoard.clearContents()
    deliveryBoard.setString("Prior", forType: .string)
    expect(observed == "Delivered", "paste sees offered clipboard")
    expect(deliveryBoard.string(forType: .string) == "Prior", "transaction restores clipboard")
    do { try await transaction.deliver("Failure", board: deliveryBoard, delay: 0.01) { throw MurmurError.empty }; expect(false, "delivery exception propagates") }
    catch { expect(deliveryBoard.string(forType: .string) == "Prior", "delivery exception restores clipboard") }
} catch { expect(false, "clipboard transaction") }
deliveryBoard.releaseGlobally()
expect(DictationLanguage.numbers("FIVE AND SIX") == "5 and 6", "capitalized conjunction does not recurse")
expect(DictationLanguage.numbers("one and hello") == "one and hello", "number conversion preserves trailing conjunction")
expect(!RewriteFidelity.accepts("Meet at 5.", selected: "Meet at 4."), "model rewrite preserves numerical facts")
expect(!RewriteFidelity.accepts("Visit another company.", selected: "Visit Acme.", protectedTerms: ["Acme"]), "model rewrite preserves protected terms")
expect(!RewriteFidelity.accepts("EUR -50 in VX-7.", selected: "USD +50 in ZX-7."), "rewrite cannot change sign and structured identifier")
expect(!RewriteFidelity.accepts("Dose is 5 mg.", selected: "Dose is .5 mg."), "rewrite preserves decimal punctuation")
expect(!RewriteFidelity.accepts("Bex pays 4 on Tuesday.", selected: "Ari pays 4 on Monday."), "rewrite preserves likely names and date words")
expect(RewriteFidelity.accepts("4 seats at Acme.", selected: "There are 4 seats at Acme.", protectedTerms: ["Acme"]), "shorter rewrite may preserve facts")
do {
    let replacement = try EditingCommand.apply("Replace 3 with 4", selected: "Meet at 3.")
    expect(replacement == "Meet at 4.", "explicit numeric replacement is deterministic")
    let verbal = try EditingCommand.apply("replace three with four", selected: "Meet at 3.")
    expect(verbal == "Meet at 4.", "spoken numeric replacement")
    let tone = try EditingCommand.apply("make it informal", selected: "Regarding the report.")
    expect(tone == "About the report.", "informal does not invoke formal styling")
} catch { expect(false, "explicit editing operations") }
do {
    let text = try EditingCommand.apply("Replace AC with Z!", selected: "AC AC-12 ACME account")
    expect(text == "Z! AC-12 ACME account", "literal replace is token-scoped and preserves operand punctuation")
    let amount = try EditingCommand.apply("Replace 3 with 4", selected: "Use 3 and leave 3.5 unchanged.")
    expect(amount == "Use 4 and leave 3.5 unchanged.", "replacement cannot match part of a decimal")
    let formal = try EditingCommand.apply("Make formal", selected: "From Paris, actually London.")
    expect(formal == "From Paris, actually London.", "formal edit does not run dictation corrections")
    do {
        _ = try EditingCommand.apply("Do not uppercase this", selected: "Case-sensitive AbC")
        expect(false, "negation is not a case command")
    } catch MurmurError.unsupportedCommand { expect(true, "negated operation rejected") }
    let program = CommandRewrite(executable: URL(fileURLWithPath: "/bin/false"), model: URL(fileURLWithPath: "/dev/null"))
    do {
        _ = try await program.rewrite(instruction: "Fix spacing", selected: "Text <|im_end|> with a role delimiter")
        expect(false, "role delimiters cannot reach the decoder")
    } catch { expect(error.localizedDescription.contains("delimiters"), "role delimiter rejected before spawn") }
} catch { expect(false, "literal edit fixtures: \(error)") }
// Delivery decisions distinguish missing grants from a changed or unreadable destination.
let focus = FocusEvidence(pid: 42, editable: true, role: "AXTextArea", text: "Hello", selection: NSRange(location: 5, length: 0))
func reason(_ current: FocusEvidence, same: Bool = true, trusted: Bool = true, selection: Bool = false) -> DeliveryReason {
    DeliveryPolicy.decide(original: focus, current: current, sameElement: same, trusted: trusted, requireSelection: selection)
}
expect(reason(focus) == .ready, "same destination inserts")
expect(reason(focus, trusted: false) == .accessibility, "missing Accessibility explains copy fallback")
var changedFocus = focus; changedFocus.protected = true
expect(reason(changedFocus, trusted: false) == .protectedField, "protected destination is blocked before fallback")
changedFocus = focus; changedFocus.pid = 99
expect(reason(changedFocus) == .targetChanged, "switching apps prevents paste")
changedFocus = focus; changedFocus.selection = NSRange(location: 0, length: 0)
expect(reason(changedFocus) == .cursorChanged, "moving cursor prevents stale paste")
changedFocus = focus; changedFocus.text = "Changed"
expect(reason(changedFocus) == .textChanged, "editing destination prevents stale paste")
changedFocus = focus; changedFocus.editable = false
expect(reason(changedFocus) == .unreadable, "non-text destination stays clipboard-only")
expect(reason(focus, same: false) == .targetChanged, "geometry cannot establish the same control")
expect(DeliveryPolicy.decide(original: focus, current: focus, sameElement: true, sameWindow: false, trusted: true) == .targetChanged, "window is required even when the AX element matches")
expect(DeliveryPolicy.decide(original: focus, current: focus, sameElement: true, trusted: true, focusChanged: true) == .targetChanged, "observed intervening focus changes prevent paste")
changedFocus = focus; changedFocus.selection = nil
expect(reason(changedFocus) == .cursorChanged, "missing previously known caret blocks paste")
changedFocus = focus; changedFocus.text = nil
expect(reason(changedFocus) == .textChanged, "missing previously known value blocks paste")
let edit = FocusEvidence(pid: 42, editable: true, selection: NSRange(location: 1, length: 2), selectedText: "🌱")
var changedEdit = edit; changedEdit.selectedText = "🌿"
expect(DeliveryPolicy.decide(original: edit, current: changedEdit, sameElement: true, trusted: true, requireSelection: true) == .textChanged, "a changed same-length selection without AXValue blocks replacement")
expect(DeliveryPolicy.decide(original: edit, current: edit, sameElement: true, trusted: true, requireSelection: true) == .ready, "same Unicode selection is eligible")
expect(!DeliveryReason.accessibility.explanation.isEmpty && DeliveryReason.shortcutHeld.explanation.contains("release"), "delivery feedback identifies a corrective action")
// Display smoothing is independent of capture chunk timing and handles silence/invalid input.
expect(AudioMeter.normalized(0) == 0 && AudioMeter.normalized(.nan) == 0, "meter ignores silence and invalid samples")
expect(AudioMeter.normalized(.infinity) == 0 && AudioMeter.normalized(-1) == 0, "meter rejects nonfinite and negative RMS")
expect(AudioMeter.normalized(1) == 1, "meter clamps clipping")
expect(AudioMeter.normalized(0.02) > AudioMeter.normalized(0.005), "speech dynamics remain ordered")
var meter = AudioMeter(); let target = AudioMeter.normalized(0.03)
let onset = meter.advance(rms: 0.03, delta: 1.0 / 60)
expect(onset > 0 && onset < target, "meter interpolates attack instead of jumping")
for _ in 0..<30 { _ = meter.advance(rms: 0.03, delta: 1.0 / 60) }
expect(abs(meter.value - target) < 0.001, "meter follows sustained voice promptly")
let peak = meter.value; let released = meter.advance(rms: 0, delta: 1.0 / 60)
expect(released > peak * 0.8 && released < peak, "meter release decays smoothly")
for _ in 0..<150 { _ = meter.advance(rms: 0, delta: 1.0 / 60) }
expect(meter.value == 0, "meter returns to rest after silence")
var sixty = AudioMeter(); var thirty = AudioMeter()
for _ in 0..<12 { _ = sixty.advance(rms: 0.02, delta: 1.0 / 60) }
for _ in 0..<6 { _ = thirty.advance(rms: 0.02, delta: 1.0 / 30) }
expect(abs(sixty.value - thirty.value) < 0.00001, "meter response is independent of refresh rate")
let opaque = FocusEvidence(pid: 42, editable: false)
expect(DeliveryPolicy.decide(original: opaque, current: opaque, sameElement: true, trusted: true) == .unreadable, "opaque container identity cannot establish keyboard focus")
expect(DeliveryPolicy.decide(original: opaque, current: focus, sameElement: false, trusted: true) == .unreadable, "late AX revelation cannot replace the initial anchor")
var activity = FocusActivity()
activity.key(49, dictationChord: true, toggleKey: 49, holdKey: nil)
expect(activity.unchanged, "dictation toggle does not invalidate keyboard focus")
activity.key(15, dictationChord: true, toggleKey: 49, holdKey: nil)
expect(activity.unchanged, "editing shortcut is recognized by focus tracking")
activity.key(49, dictationChord: false, toggleKey: 49, holdKey: nil)
expect(!activity.unchanged, "ordinary space typing invalidates opaque focus")
activity.key(49, dictationChord: true, toggleKey: 49, holdKey: nil)
expect(!activity.unchanged, "another toggle cannot clear recorded focus changes")
activity = FocusActivity(); activity.key(124, dictationChord: false, toggleKey: 49, holdKey: nil)
expect(!activity.unchanged, "arrow-key cursor movement invalidates opaque focus")
activity = FocusActivity(); activity.key(97, dictationChord: false, toggleKey: 49, holdKey: 97)
expect(activity.unchanged, "configured physical hold trigger does not invalidate focus")
activity = FocusActivity(); activity.key(97, dictationChord: false, toggleKey: 49, holdKey: 97, standaloneHold: false)
expect(!activity.unchanged, "modified F6 is ordinary input, even with F6 hold enabled")
activity = FocusActivity(); activity.key(97, dictationChord: false, toggleKey: 49, holdKey: nil)
expect(!activity.unchanged, "disabled hold key can change focus and must invalidate")
activity = FocusActivity(); activity.invalidate()
expect(!activity.unchanged, "pointer interaction or a lost event tap invalidates focus")
print("\(checks - failed)/\(checks) checks passed")
exit(failed == 0 ? 0 : 1)

 }
}
