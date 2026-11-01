# Remaining-work implementation audit

This pass implements the gaps identified after the initial delivery. The analysis bridge stays closed.

- Configurable physical hold key, correct press/release ownership, and preference migration.
- Destination categories with local-only context and protection of code/terminal text.
- Broader deterministic cleanup fixtures for corrections, numbers, dates, and lists.
- An integrated optional on-device cleanup stage with a strict deadline and measured eligibility; failing qualification keeps rules active.
- A repeatable speech-engine comparison with explicit unavailable/error results.
- Native self-tests and integration diagnostics for real text controls, undo, clipboard handling, feedback, and permission links.
- Complete settings, error handling, and documentation for the new controls.

Actual cross-application tests and microphone measurements remain pending until macOS grants access. Streaming partial recognition, headset buttons, and whisper mode remain deferred as specified in the brief.
