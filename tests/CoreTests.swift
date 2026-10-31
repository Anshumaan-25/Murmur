import Foundation
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
print("\(checks - failed)/\(checks) checks passed")
exit(failed == 0 ? 0 : 1)

 }
}
