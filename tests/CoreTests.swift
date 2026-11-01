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
expect(!TextGuard.accepts("Here is an answer with unrelated content", original: "Send the invoice."), "unrelated model output rejected")
expect(!TextGuard.accepts("Meet at 5.", original: "Meet at 4."), "changed number rejected")
expect(TextGuard.accepts("Send the note.", original: "Send the note."), "faithful output allowed")
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
expect(RecordingPolicy.shouldFinish(duration: 5, silence: 2, heardSpeech: true, handsFree: true, silenceLimit: 1.5, maximum: 120), "hands-free ends on silence")
expect(!RecordingPolicy.shouldFinish(duration: 5, silence: 2, heardSpeech: true, handsFree: false, silenceLimit: 1.5, maximum: 120), "toggle ignores silence")
expect(RecordingPolicy.shouldFinish(duration: 120, silence: 0, heardSpeech: false, handsFree: false, silenceLimit: 1.5, maximum: 120), "duration cap always enforced")
expect(RecordingPolicy.returnIntent("Send it press enter.", enabled: true).text == "Send it", "terminal return intent extracted")
expect(!RecordingPolicy.returnIntent("Press enter to continue", enabled: true).pressReturn, "embedded return phrase remains text")
expect(!RecordingPolicy.returnIntent("Send it press enter", enabled: false).pressReturn, "return disabled by default")
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
    expect(edited == "I cannot attend.", "local editing without model")
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
    let invalid = try JSONDecoder().decode(Preferences.self, from: Data(#"{"language":"en-IN","holdKey":"futureKey","maximumSeconds":-1}"#.utf8))
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
expect(CleanupFidelity.accepts("Hello, world.", baseline: "Hello world.", dictionary: []), "model can adjust punctuation")
expect(!CleanupFidelity.accepts("Try acme.", baseline: "Try Acme.", dictionary: ["Acme"]), "model must preserve dictionary spelling")
let timerBegan = Date()
do { _ = try await Deadline.run(seconds: 0.03) { try await Task.sleep(nanoseconds: 2_000_000_000); return "late" }; expect(false, "deadline rejects slow work") }
catch { expect(Date().timeIntervalSince(timerBegan) < 0.5, "deadline returns promptly") }
do { let answer = try await Deadline.run(seconds: 1) { 42 }; expect(answer == 42, "deadline returns fast work") }
catch { expect(false, "deadline fast work succeeds") }
let deadlineTask = Task { try await Deadline.run(seconds: 10) { try await Task.sleep(nanoseconds: 10_000_000_000); return 7 } }
deadlineTask.cancel()
do { _ = try await deadlineTask.value; expect(false, "deadline propagates caller cancellation") } catch { expect(true, "deadline propagates caller cancellation") }
expect(!CleanupFidelity.accepts("Great.", baseline: "Great!", dictionary: [], preservePunctuation: true), "explicit punctuation retained")
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
    expect(observed == "Delivered", "paste sees offered clipboard")
    expect(deliveryBoard.string(forType: .string) == "Prior", "transaction restores clipboard")
    do { try await transaction.deliver("Failure", board: deliveryBoard, delay: 0.01) { throw MurmurError.empty }; expect(false, "delivery exception propagates") }
    catch { expect(deliveryBoard.string(forType: .string) == "Prior", "delivery exception restores clipboard") }
} catch { expect(false, "clipboard transaction") }
deliveryBoard.releaseGlobally()
expect(DictationLanguage.numbers("FIVE AND SIX") == "5 and 6", "capitalized conjunction does not recurse")
expect(DictationLanguage.numbers("one and hello") == "1 and hello", "number conversion preserves trailing conjunction")
expect(!RewriteFidelity.accepts("Meet at 5.", selected: "Meet at 4."), "model rewrite preserves numerical facts")
expect(!RewriteFidelity.accepts("Visit another company.", selected: "Visit Acme.", protectedTerms: ["Acme"]), "model rewrite preserves protected terms")
expect(RewriteFidelity.accepts("Acme: 4 seats.", selected: "There are 4 seats at Acme.", protectedTerms: ["Acme"]), "shorter rewrite may preserve facts")
do {
    let replacement = try EditingCommand.apply("Replace 3 with 4", selected: "Meet at 3.")
    expect(replacement == "Meet at 4.", "explicit numeric replacement is deterministic")
    let verbal = try EditingCommand.apply("replace three with four", selected: "Meet at 3.")
    expect(verbal == "Meet at 4.", "spoken numeric replacement")
    let tone = try EditingCommand.apply("make it informal", selected: "Regarding the report.")
    expect(tone == "About the report.", "informal does not invoke formal styling")
} catch { expect(false, "explicit editing operations") }
// Delivery decisions distinguish missing grants from a changed or unreadable destination.
let focus = FocusEvidence(pid: 42, editable: true, identifier: "draft", role: "AXTextArea", bounds: [10, 20, 400, 200], text: "Hello", selection: NSRange(location: 5, length: 0))
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
expect(reason(focus, same: false) == .ready, "stable identity supports recreated accessibility wrappers")
expect(DeliveryPolicy.decide(original: focus, current: focus, sameElement: false, sameWindow: false, trusted: true) == .targetChanged, "matching identifiers in another window cannot receive paste")
changedFocus = focus; changedFocus.bounds = [200, 20, 400, 200]
expect(reason(changedFocus, same: false) == .targetChanged, "identifier alone cannot identify a moved replacement control")
var geometryFocus = focus; geometryFocus.identifier = nil
expect(DeliveryPolicy.decide(original: geometryFocus, current: geometryFocus, sameElement: false, trusted: true) == .ready, "matching bounds text and cursor identify recreated field")
changedFocus = geometryFocus; changedFocus.bounds = [11, 21, 400, 200]
expect(DeliveryPolicy.decide(original: geometryFocus, current: changedFocus, sameElement: false, trusted: true) == .ready, "subpixel accessibility geometry variation is tolerated")
changedFocus.bounds = [200, 200, 400, 200]
expect(DeliveryPolicy.decide(original: geometryFocus, current: changedFocus, sameElement: false, trusted: true) == .targetChanged, "different field geometry prevents paste")
changedFocus = geometryFocus; changedFocus.selection = nil
expect(DeliveryPolicy.decide(original: geometryFocus, current: changedFocus, sameElement: false, trusted: true) == .targetChanged, "missing evidence cannot establish a replacement field")
changedFocus = focus; changedFocus.selection = nil
expect(reason(changedFocus, selection: true) == .unreadable, "selected-text edits require a readable selection")
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
print("\(checks - failed)/\(checks) checks passed")
exit(failed == 0 ? 0 : 1)

 }
}
