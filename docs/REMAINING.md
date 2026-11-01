# Remaining-work implementation audit

This pass implements the gaps identified after the initial delivery. The analysis bridge stays closed.

- [x] Configurable physical hold key, correct press/release ownership, and preference migration.
- [x] Destination categories with local-only context and protection of code/terminal text.
- [x] Broader deterministic cleanup fixtures for corrections, numbers, dates, and lists.
- [x] An integrated optional on-device cleanup stage with a strict deadline and measured eligibility; failing qualification keeps rules active.
- [x] A repeatable speech-engine comparison with explicit unavailable/error results.
- [x] Native self-tests and integration diagnostics for real text controls, undo, clipboard handling, feedback, and permission links.
- [x] Complete settings, error handling, and documentation for the new controls.

Actual cross-application tests and microphone measurements remain pending until macOS grants access. Streaming partial recognition, headset buttons, and whisper mode remain deferred as specified in the brief.


All listed implementation items passed the build gate. Automatic cleanup qualified on this computer and stays optional. The broader engine run records each available and unavailable candidate explicitly. Full live microphone, physical key, fullscreen-Space and external-application acceptance still requires the corresponding macOS grants. Direct Accessibility writes remain disabled because undo reliability has not been established in external targets; normal paste preserves the destination's undo mechanism.
