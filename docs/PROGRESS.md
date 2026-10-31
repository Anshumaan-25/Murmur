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
