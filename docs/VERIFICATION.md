# Current verification record

The remaining-work pass was tested on this Apple M5 MacBook Air with 16 GiB RAM, macOS 27.0.1, and Swift 6.4. Earlier delivery measurements remain in VERIFICATION.json; the current results are in REMAINING_VERIFICATION.json.

## Passing checks

- 229 compiled core checks, including ninety deterministic text fixtures, preference migration, hold-gesture state, app categories, syntax preservation, deadlines, cancellation, numerical fidelity, model guards, SQLite and pasteboard behavior.
- Native app-owned controls: selected replacement, undo/redo, Unicode paste, all saved clipboard data, newer-owner protection, failure recovery, nonactivating window properties, Space/fullscreen collection flags, and registered handlers for privacy-setting links.
- The build checkpoint requires the core suite, release application packaging, strict code-signature verification, clean-room scanning, and native-control checks.
- Optional system-model cleanup passed all ninety expected outputs under a network-denial policy. Its 95th percentile was 0.426 seconds; 77 cases used model output and the others used safe fallback. The qualification record binds the OS, rule revision, fixture fingerprint, and a seven-day age limit. The runtime model deadline is 800 milliseconds.

## Speech selection

The fixed synthetic clip set produced the same mean normalized word error, 1.56%, for the original GPU path, CPU path and compact five-bit model. Medians including decoder startup were 0.458, 0.935 and 0.378 seconds respectively. The compact variant is selected, with its source and derived checksums recorded in SPEECH_VARIANT.json.

Both system speech APIs were attempted and returned explicit unavailable results: the analyzer lacked ready assets, and the older recognizer lacked authorization. Additional model frameworks were not installed within this bounded comparison. SPEECH_COMPARISON.json contains every measured or unavailable sample; unavailable paths have no invented latency or accuracy score.

## Complete synthetic-input path

A ten-second PCM fixture was processed through the packaged recognizer, cleanup, an actual native text view, and the configured 350 ms clipboard-recovery interval. Three rule-only runs measured 0.843, 0.748 and 0.756 seconds, giving a 0.756-second median. Three network-denied runs with optional cleanup measured 1.533, 1.349 and 1.346 seconds, giving a 1.349-second median. Model output was accepted in two of those three runs; the deadline/fidelity path safely fell back in the other.

Native indicator paint-dispatch checks were about 3–6 ms. Hardware microphone start and physical screen composition were outside those measurements. Runtime Settings now records event-to-indicator paint dispatch and release-to-successful-insertion samples in memory, without text or audio.

## OS-dependent acceptance

On 2026-11-01, the running `/Applications/Murmur.app` reported Microphone, Accessibility and Input Monitoring all granted through a GUI-origin diagnostic. Command-line child diagnostics can have a different TCC context and do not override that evidence. Input Monitoring is needed for physical hold keys; system dictation additionally needs Speech Recognition authorization. The registered toggle remains independent of Input Monitoring.

The updated native suite has 16 passing checks, with a 16.668 ms median visible-indicator timer interval. `python3 scripts/cross_app_check.py` checks actual Unicode paste into separate native, WebKit and opaque-editor fixtures. Native and opaque-editor undo/redo pass. Its negative case posts a cursor key into the disposable opaque fixture and verifies that the result is copied without inserting. A missing intended focus is a skip, not permission to paste into another app.

Codex's actual window exposed AXGroup objects rather than a focused editable field. After the repair, a GUI-origin delivery-readiness probe returned `ready` with focus monitoring available and unchanged; the probe posted no input. This is evidence for the corrected Codex delivery policy, not a transcript-readback or live microphone test.

Live microphone quality, physical shortcut handling, the system globe action, fullscreen Spaces, exact privacy-pane navigation, launch-at-login registration, and a complete dictated utterance in the user's third-party apps remain manual acceptance items. Opaque-editor automatic insertion uses Input Monitoring in addition to Accessibility; ordinary accessible-field insertion retains its existing checks.

Open Murmur → Settings, grant the needed permissions, and follow MANUAL_TESTS.md. Optional cleanup can be enabled after validation qualifies on the current computer; it defaults to rules. No cloud adapter, account, telemetry, or reference-application runtime access is part of the implementation.
