# Progress

## Environment and specification

Completed environment inventory and bounded evidence review. Specification bridge is closed. Full IDE is absent; command line compiler and SDK are usable. Microphone and Accessibility status must be evaluated from the signed app, since grants belong to a requesting executable. Model availability and one-time download authorization are pending runtime probes.

## M1 — Native shell

Menu-bar application, permission controls, startup registration, app bundler, isolated signing identity, and six session checks implemented. The release binary compiled and signature verification passed using the project keychain. Privacy settings pane dispatch is implemented; exact pane selection and manual grants still require GUI verification. Provider groundwork is included for the next milestone. The original command line test-framework and UI-macro limitations were resolved without global installations.

## M2 — Capture and recognition

Native raw microphone capture, conversion, bounded sample batches, silence trimming, registered toggle shortcut, local speech provider interfaces, and a transcript preview are implemented. Decoder input uses an anonymous pipe. Synthetic speech benchmarks run without microphone permission. System speech is retained as an interchangeable adapter but asset readiness is not assumed from installed locale listings. Physical microphone testing remains gated by the user's OS grant.
