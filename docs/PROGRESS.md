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

## Remaining-work pass: input and context

Added configurable physical hold keys, deduplicated press/release handling, hold-session ownership, destination categories, syntax preservation, and backwards-compatible settings. Added local system-dictation and on-device cleanup adapters plus a cancellable deadline primitive. The new gate passes 115 checks. Automatic model cleanup still requires qualification before it can be selected.

## Remaining-work pass: cleanup and verification

Expanded deterministic editing to ninety fixtures and protected emphasis, multiword names, times, decimals, percentages, dates, and conjunctions. The optional system-model stage now passes 90/90 output expectations with content/punctuation guards; a network-denied run accepted model output in 77 cases and measured a 0.426 second 95th percentile. Its qualification is tied to the OS, fixture digest, rule revision and age.

The engine comparison found the compact local speech variant faster at the same measured synthetic error rate. Packaging verifies its checksum and setup reproduces it from the approved original weights. The full gate currently passes 186 core checks plus native text-control, Unicode, undo/redo, clipboard ownership, failure-recovery, panel and settings-handler checks. Ten-second synthetic-input pipeline medians were 0.756 seconds with rules and 1.349 seconds with optional cleanup, including clipboard recovery. These are app-owned fixture measurements, not a claim of microphone or external-app acceptance.

Final onboarding refinement: the Accessibility and Input Monitoring buttons now request the corresponding OS grant when clicked, then open its Settings pane. Automated checks do not invoke those interactive requests. The current app still reports those grants as missing until the user enables them.

## Delivery repair and visual refresh — 2026-11-01

The launched installed app reports Microphone, Accessibility and Input Monitoring granted. Earlier shell-only probes did not establish the GUI process's permission state. Added an explicit GUI-origin metadata diagnostic and precise clipboard-fallback explanations, also saved in new history outcomes. No additional grant is required by the current installed app.

Delivery now handles a lazily constructed accessibility editor with a bounded asynchronous retry, recognizes sufficiently identified recreated wrappers, waits for Control/Option release, and revalidates the destination before paste. Paste events use an isolated source and clear their synthetic modifier flags on release. App, window, field, cursor, text and protected-field checks remain active.

Replaced per-audio-buffer main-queue UI work with a latest-value microphone meter and time-based smoothing. The redesigned floating indicator samples at a 60 Hz target while visible, with fast attack, gentle release and no hidden animation timer. The native fixture measured a median 16.668 ms update interval and about 3.2 ms initial paint dispatch; these are timer/dispatch measurements, not physical display latency.

Rebuilt the hub with a dark sidebar, lavender/mint accents, usage tiles, original wave artwork, editor placeholders, sectioned settings, permission status, hover feedback, page fades and an original Finder icon. Inspected all five pages and the indicator via app-owned, private-content-free previews. Added a signed installation target.

Verification: 211 core checks and 16 native checks pass, including meter response and timer shutdown. A separate native fixture received Unicode text through actual Command-V before the screen locked. A WebKit fixture demonstrated initially missing accessibility focus that became readable after a retry. Final native/web integration reruns were stopped by the locked login session, which correctly refused insertion; web delivery and physical microphone acceptance are not claimed. The optional cross-app script uses disposable fixtures, a required target bundle, clipboard restoration and explicit skip behavior when the fixture is not focused.

## Opaque-editor insertion repair — 2026-11-01

The user's repeated clipboard fallbacks were reproduced in the metadata: recent Codex sessions were `copied: unreadable` despite all three permissions being granted. Codex exposed its window and opaque AXGroup objects, while a focused editable field was absent. Requiring an AX text-field identity for every plain dictation was the product defect.

Added recording-scoped focus continuity. An ordinary paste is allowed in an opaque editor only while the original app and known window remain the same, the listen-only event tap remains valid, and no typing, cursor key, click or app activation has invalidated focus. Dictation/hold triggers are excluded from this Boolean activity flag; no keys or coordinates are stored. Cancellation and completion remove the event tap. Protected inputs and selected-text rewriting retain their stronger checks. Opaque container text can change as the surrounding document updates without being mistaken for an edit to the keyboard destination.

The gate passes 229 core and 16 native checks. External fixtures now include a native editor, a WebKit textarea, an editor deliberately exposing no focused AX element, and the opaque editor after a cursor-key event. Actual Unicode paste and native/opaque undo/redo pass; cursor movement correctly produces a copied result without modifying the editor. A non-mutating check from the running GUI app against the actual Codex window returned `ready`, `focus_tracking_available: true`, `focus_unchanged: true`, and `posted_input: false` with AXGroup roles. This establishes the corrected eligibility path; no test transcript was sent into the user's Codex chat.

## Keydown rename — 2026-11-06

Renamed the app, menu items, dictation indicator, installation bundle, and app commands to Keydown. Verified that the running app at `/Applications/Keydown.app` retains Microphone, Accessibility, and Input Monitoring grants. The saved preferences fingerprint and all four local data table counts matched before and after installation. The old app bundle was archived in the project’s ignored `.local` directory. The checkpoint passed all 229 core checks, native control tests, clean-room scan, and strict signature verification.
