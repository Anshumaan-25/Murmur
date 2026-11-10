# Known issues and qualification limits

Version 0.2.3 addresses the remaining confirmed implementation findings from the prior reviews:

- **SC-ADV-01:** space-grouped numeric corrections now preserve the complete ambiguous statement, including ordinary, nonbreaking and narrow nonbreaking spaces. Numeric/time/repeated-unit replacements refuse interior matches next to digit groups or spaced structural connectors.
- **SC-ADV-02:** weekday corrections require standalone operands; compound weekday IDs remain literal. Name corrections use conservative title-case operands so all-caps ID components are not guessed to be names. Unsupported notation remains visible rather than silently constructing a new value.
- **KP-POST-02:** completed local speech-classifier evidence is required before automatic delivery or interpreting a selected-text edit. Uncertain/noise-only recognition is retained for deliberate review. The decoder itself may still invent words from noise; the delivery gate addresses that consequence rather than claiming recognition is infallible.
- **KP-POST-03:** hands-free stopping uses classifier speech/silence timestamps instead of learning the first 300 ms as a volume baseline. Uncertain sound cannot be treated as clear silence. Hold release, explicit stop and duration limits remain effective.
- **MP-TEST-01:** native fixtures inject a capture-start spy at the production start boundary. Positive ordering, cancellation, hold release, sleep, old/new session overlap, permission denial and pause-disabled capture are observed directly without opening a microphone.

Cleanup revision is now cleanup-7; earlier model qualification must be renewed. Exact mode continues to preserve literal text. Selected-text model suggestions remain review-and-copy only; name/meaning checks are advisory.

Physical qualification remains open: actual microphones, accents and very short/quiet utterances, real room noise, simultaneous media players, Bluetooth audio routes, sleep/wake display behavior, external-app insertion/undo and accessibility. Sound classification is probabilistic and cannot establish speaker identity or intent. See SPEECH_SAFETY.md, MEDIA_PAUSE.md and MANUAL_TESTS.md. New post-development adversarial findings, if any, are reported separately before further fixes.

## Residuals found by the 0.2.3 post-development review

- **Mixed speech and noise:** two confident windows establish speech somewhere in a recording, not that every decoded word is supported. A synthetic speech clip followed by 60 seconds of noise still qualified and the decoder appended invented prose. Pure-noise sessions are gated, but mixed recordings need segment-aware decoding or mandatory review when substantial uncertain/noise spans remain.
- **Uncommon spaced ID connectors:** `Reference 123 : 456 actually make that 789.` can still become `Reference 123: 789.`; spaced middle-dot and pipe connectors also bypass the finite adjacency guard. Complete structured-span tokenization is needed, including unknown connectors, before automatic correction.

Both residuals were reproduced by the independent reviewer and intentionally left unpatched in this iteration under the requested report-before-further-fixes workflow. They were not introduced by the new gate; the gate does not fully resolve all pre-existing hallucination cases. Prioritize mixed-audio delivery, then category-level structured operand parsing.
