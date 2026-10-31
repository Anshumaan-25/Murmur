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
 static func main() async {
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
print("\(checks - failed)/\(checks) checks passed")
exit(failed == 0 ? 0 : 1)

 }
}
