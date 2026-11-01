# Murmur

A personal macOS dictation utility with local recognition and local text editing.

Requires macOS 26 or later and Swift command line tools. Build with `make app`, launch with `make run`, and verify with `make test`. No package dependencies are needed for the basic native application.

Before granting permissions, run `bash scripts/create_signing_identity.sh` then rebuild. This creates a private project keychain rather than using the login keychain. Without that identity, builds use ad hoc signatures and macOS may require renewed grants after a rebuild. Keep the application at the same path.

Enable microphone access when prompted. Enable Murmur in Accessibility to paste into another application. Input Monitoring is optional for the globe/function hold shortcut. Onboarding opens the relevant System Settings pane. Enable launch at login from the hub if desired.

Audio is transient by default. Recognition and editing providers are local. Model downloads require an explicit confirmation and checksum validation. No accounts or telemetry are included.

## Models and reproducible setup

The app built on this machine already bundles its verified English speech decoder and selected-text editing model. Models and engine build trees are intentionally ignored by Git. Their pinned checksums and source revisions are in `docs/MODELS.json` and `docs/ENGINES.json`.

From another checkout, run `python3 scripts/download_models.py --confirm`. Set `MURMUR_SPEECH_SOURCE` to the upstream whisper.cpp repository URL or an existing source checkout, and run `bash scripts/setup_engines.sh`. To build editing as well, set `MURMUR_TEXT_SOURCE` to the upstream llama.cpp source and `MURMUR_BUILD_EDITING=1`. No global installation is required; a missing build generator is installed inside `.local`.

A checkout without downloaded resources still compiles and uses the system speech adapter. That adapter requires language assets which macOS reports as ready; it never initiates an asset download. On this machine, locale listings did not match asset readiness, so the bundled decoder is the tested choice.

## Daily use

- Control Option Space starts or finishes dictation. The Settings page can change the toggle to Control Option D.
- The hold key is configurable: Fn/globe, Right Option, Right Control, Right Shift, or F6. Holding it records until release after Input Monitoring is enabled. Set the system globe action to Do Nothing to avoid the emoji picker.
- Escape cancels a live session. Control Option V inserts the most recent result.
- Select text and press Control Option R to dictate an editing request. Common casing/tone/shortening edits are deterministic; other requests can use the local model and take several seconds.
- Hands-free mode ends a recording after speech followed by silence. The duration cap applies in every mode.
- A changed target receives a copied result. Protected fields receive no injected text. The prior clipboard is restored after a normal paste unless another application copied new content meanwhile.

The hub contains history, vocabulary, spoken expansions, app styles, and settings. History records recognized, cleaned, and delivered text independently. The audio-retention switch is off by default. Optional automatic cleanup uses the installed on-device system model after passing the bundled quality and timing suite. In Settings, choose Validate local cleanup, then enable the qualified option. Qualification expires after an OS/rule/fixture change or seven days. An 800 ms deadline and content/punctuation checks fall back to rules. The slower downloaded model remains available for explicitly requested selected-text edits.

Run `bash scripts/checkpoint.sh` for the complete build gate. `bash scripts/demo.sh` builds and verifies without activating the microphone. The remaining permission-gated acceptance steps are in `docs/MANUAL_TESTS.md`. Benchmark values and their limits are in `docs/BENCHMARK.json`.


## Input behavior and diagnostics

Destination categories are inferred locally. Code editors and terminals preserve exact syntax by default; Settings can disable that behavior. Existing preferences migrate field by field. The optional system-dictation provider requires its separate Speech Recognition grant; Automatic uses the bundled local decoder whenever available.

The setup script derives a compact speech model locally from the checksum-verified original, using the pinned engine revision. `docs/SPEECH_VARIANT.json` records both digests; no additional model download is involved. The compact variant is selected after the comparison in `docs/SPEECH_COMPARISON.json`.

`python3 scripts/compare_engines.py` repeats the bounded local engine comparison. `bash scripts/native_checks.sh` verifies native controls, undo/redo, Unicode, clipboard restoration and the nonactivating panel without microphone access. Add `--audio tests/audio/ten-seconds.wav` for synthetic-input pipeline timing, and `--with-cleanup` for the qualified optional model. Generate those synthetic clips with `make bench` first. These checks use an app-owned text view; external applications remain covered by the permission-gated integration script and manual checks.

Settings reports in-memory indicator paint-dispatch and successful insertion timing for the current launch. No audio or text is included in those measurements.
