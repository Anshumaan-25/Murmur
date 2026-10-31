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
- Holding Fn/globe records until release after Input Monitoring is enabled. Set the system globe action to Do Nothing to avoid the emoji picker.
- Escape cancels a live session. Control Option V inserts the most recent result.
- Select text and press Control Option R to dictate an editing request. Common casing/tone/shortening edits are deterministic; other requests can use the local model and take several seconds.
- Hands-free mode ends a recording after speech followed by silence. The duration cap applies in every mode.
- A changed target receives a copied result. Protected fields receive no injected text. The prior clipboard is restored after a normal paste unless another application copied new content meanwhile.

The hub contains history, vocabulary, spoken expansions, app styles, and settings. History records recognized, cleaned, and delivered text independently. The audio-retention switch is off by default. Automatic model cleanup is disabled because its measured cold latency exceeded the gate. It is distinct from explicitly requested selected-text editing.

Run `bash scripts/checkpoint.sh` for the complete build gate. `bash scripts/demo.sh` builds and verifies without activating the microphone. The remaining permission-gated acceptance steps are in `docs/MANUAL_TESTS.md`. Benchmark values and their limits are in `docs/BENCHMARK.json`.
