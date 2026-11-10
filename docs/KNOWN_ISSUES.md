# Known issues

The independent post-fix review found the following residuals; passing automated checks does not qualify all dictation for automatic delivery.

- **Medium — spaced numeric operands:** `Pay 1 205 actually make that 2 500.` can become `Pay 1 2 500.`. Nonbreaking and narrow nonbreaking spaces have the same ambiguity. Correction parsing still needs to recognize grouped amounts as whole operands.
- **Low — weekday fragments in IDs:** `Reference ABC-Monday actually make that Tuesday.` can become `Reference ABC-Tuesday.`. The separate weekday rule needs the same whole-operand protection as numeric corrections.
- **Medium — noise hallucination:** a 60-second synthetic noise fixture produced invented prose through the bundled decoder. Rejecting a complete `[BLANK_AUDIO]` sentinel fixes the short fixture, but does not establish speech presence. Automatic delivery needs qualified speech evidence, with deliberate review for uncertain input while preserving valid quiet speech.
- **Low — hands-free calibration:** speech during the first 300 ms can become the noise baseline and prevent silence completion. Changing noise can also refresh the activity clock. Use explicit stop or hold release; cancellation and the duration cap remain effective. The energy fallback needs real microphone qualification.

Selected-text model suggestions remain review-and-copy only. Unconfigured names and arbitrary meaning changes cannot be guaranteed by the advisory fidelity check.

Fixed in 0.2.2 (cleanup-6): numeric corrections now require complete whitespace-delimited operands of the same supported kind. The tested attached slash dates/IDs, multi-part versions and attached currency or numeric identifier fragments now stay literal. This does not resolve space-grouped amounts or the separate weekday branch above. Numeric compounds with letter components stay protected during punctuation cleanup. Parenthesized values and unsupported notation remain conservative; Exact text remains available for verbatim delivery. Existing cleanup qualification must be renewed for the changed rules and expanded fixtures.

Next implementation order: complete grouped-amount and weekday operand validation, then qualify speech detection and delivery together. The two correction residuals were reported by the post-development reviewer and deliberately left for the next iteration. Physical sleep/wake visibility, external-app insertion/undo, microphone/noise, accessibility and signed-upgrade checks remain in `MANUAL_TESTS.md`. No new security vulnerability was confirmed in this bounded follow-up review.
