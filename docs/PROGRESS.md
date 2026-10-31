# Progress

## Environment and specification

Completed environment inventory and bounded evidence review. Specification bridge is closed. Full IDE is absent; command line compiler and SDK are usable. Microphone and Accessibility status must be evaluated from the signed app, since grants belong to a requesting executable. Model availability and one-time download authorization are pending runtime probes.

## M1 — Native shell

Menu-bar application, permission controls, startup registration, app bundler, isolated signing identity, and six session checks implemented. The release binary compiled and signature verification passed using the project keychain. Privacy settings pane dispatch is implemented; exact pane selection and manual grants still require GUI verification. Provider groundwork is included for the next milestone. The original command line test-framework and UI-macro limitations were resolved without global installations.

## M2 — Capture and recognition

Native raw microphone capture, conversion, bounded sample batches, silence trimming, registered toggle shortcut, local speech provider interfaces, and a transcript preview are implemented. Decoder input uses an anonymous pipe. Synthetic speech benchmarks run without microphone permission. System speech is retained as an interchangeable adapter but asset readiness is not assumed from installed locale listings. Physical microphone testing remains gated by the user's OS grant.

## M3 — Destination and clipboard

Per-session cancellation and stale-result rejection now guard insertion. The destination snapshot includes app, focused element, selection, and available text. Protected inputs are refused. Changed/unreadable targets receive a copied result. Pasteboard snapshots preserve every readable type across all items; restoration respects a newer clipboard owner. Added native clipboard round-trip checks with custom binary data and multiple items. Cross-application insertion and undo checks are documented rather than claimed without Accessibility permission. Direct Accessibility replacement is deliberately not used where undo reliability is unknown.

## M4 — Indicator and hold gesture

Added an original nonactivating floating indicator with live microphone level, transient state messages, cross-Space/fullscreen collection behavior, and saved edge docking. Fn hold handling is available when Input Monitoring is granted; the toggle remains independent. The app explains the system emoji-picker conflict and rechecks monitoring on activation. Fullscreen focus and the hardware globe gesture require the manual checks.

## M5 — Rules, context, and local history checkpoint

Implemented deterministic cleanup with forty golden cases, output fidelity guards for optional local generation, destination identity context, SQLite history containing recognition/edited/delivered text, and retention policies. The optional 1.5B four-bit model took 5.389 seconds cold and is disabled because it fails the latency gate. No recording is written by default; explicit audio retention is a local preference.

Measured speech-only synthetic median: 0.459 seconds including decoder process startup. Mean normalized word error: 2.1%. Full ten-second release-to-paste, microphone startup, and app-specific compatibility remain manual acceptance items because OS grants are absent. Tests cover cleanup, session invalidation, audio handling, clipboard round trips, and actual SQLite operations.

The user explicitly authorized continued work through the extras; this records the requested checkpoint without pausing. Continue with dictionary, expansion, styles, hands-free controls, editing commands, and hub editors.

## M6 — Vocabulary and spoken expansions

Dictionary terms persist in SQLite and are supplied to supporting recognition adapters as vocabulary hints, then used for canonical spelling. Exact spoken expansion triggers substitute the saved text without running cleanup over its formatting. Tests cover deduplication, spelling, exact-match behavior, and persistence. Editors are being integrated into the hub milestone.

Verification correction: core tests passed at M4/M5, but the packaging compile exposed an overly complex numeric expression in the indicator. It was simplified to explicit native coordinate types. Subsequent checkpoints use a fail-fast script requiring tests, application build, clean-room verification, and signature verification before a commit.

## M6 editor delivery

The hub now includes vocabulary and spoken expansion editors. They save canonical names, multiline replacements, and exact standalone triggers in the local database. Entries can be removed by clearing their trigger and saving. The native app compiled successfully with these editors.

## M7 — App styles and optional local context

The hub selects an application bundle and saves its neutral/formal/casual style. Conservative style edits are tested independently. When explicitly enabled, selected and neighboring text contribute a bounded set of capitalized spelling hints; the context stays local and protected targets remain excluded. Tests cover per-app persistence and deletion. Recognition quality with app-derived names still requires real dictation samples.

## M8 — Hands-free and repeated insertion

Hands-free recording stops after voiced audio followed by the selected silence interval, with a maximum duration independent of mode. The previous-text shortcut is available. Optional return-key intent is extracted only at the utterance end and is off by default. Added deterministic boundary tests and a real child-process cancellation check so cancelled recognition does not continue consuming resources.

## M9 — Selected-text commands

The command shortcut captures the original selection, recognizes a spoken editing request, and replaces only the unchanged destination using a paste operation owned by the target app's undo stack. Known casing/tone/shortening edits run deterministically. Other edits can use the downloaded local instruction model with a twenty-second deadline and output-size validation; model edits are separate from the disabled automatic cleanup pass. Unsupported requests are explicit when the model is absent. Unit checks cover deterministic edits and unsupported behavior; actual replacement and undo remain permission-gated manual checks.

## M10 — Hub and settings

Delivered searchable history with recognized/cleaned/delivered details, copy/delete/JSON export, aggregate word count, dictation WPM and day streaks. Added vocabulary, expansion and app-style editors; microphone, English locale, shortcut, local-context, recording, silence, duration and clipboard settings; history retention; startup controls; and local-model selection. Native window rendering is inspected through an app-owned bitmap path without capturing other applications. The optional automatic model pass remains disabled after its timing failure.

The final core gate currently passes 89 checks. The bundled recognizer also succeeded under an explicit network-denial policy from a temporary working directory. Its first such run took 4.851 seconds; three warmed network-denied runs took 0.436–0.459 seconds. Reported decoder medians do not stand in for microphone-to-insertion measurements. A real selected-text model example took 5.163 seconds and produced a shorter passage while retaining its numeric detail. The TextEdit automation script returned its documented skip status because Accessibility is not granted.

## Final delivery

M1–M10 implementation is committed. A fresh checkout passed the test, app-build, and launch commands. The main signed app is available in the project build directory, with both verified models and dependency license notices bundled. It was relaunched after stopping only the temporary checkout instance. Detailed measured results, known limits, and the exact remaining OS checks are recorded in VERIFICATION.md and VERIFICATION.json. No permission prompts need a chat response; macOS grants remain the user's direct action.
