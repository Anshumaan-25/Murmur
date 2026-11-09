# Known issues in the 0.2.0 candidate

The implementation passes 336 Swift checks, 12 Python tests and 46 native integration checks. The independent post-fix review still found these residuals; passing automated checks does not qualify all dictation for automatic delivery.

- **Medium — partial structured-value correction:** `Reference 123/456 actually make that 789.` can become `Reference 123/789.`. Numeric correction needs whole-operand validation across all branches. Use Exact text when preserving structured values is essential.
- **Medium — noise hallucination:** a 60-second synthetic noise fixture produced invented prose through the bundled decoder. Rejecting a complete `[BLANK_AUDIO]` sentinel fixes the short fixture, but does not establish speech presence. Automatic delivery needs qualified speech evidence, with deliberate review for uncertain input while preserving valid quiet speech.
- **Low — hands-free calibration:** speech during the first 300 ms can become the noise baseline and prevent silence completion. Changing noise can also refresh the activity clock. Use explicit stop or hold release; cancellation and the duration cap remain effective. The energy fallback needs real microphone qualification.

Selected-text model suggestions remain review-and-copy only. Unconfigured names and arbitrary meaning changes cannot be guaranteed by the advisory fidelity check.

Next implementation order: validate complete structured correction operands, then qualify speech detection and delivery together. Physical sleep/wake visibility, external-app insertion/undo, microphone/noise, accessibility and signed-upgrade checks remain in `MANUAL_TESTS.md`. No new security vulnerability was confirmed in this bounded follow-up review.
