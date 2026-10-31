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
