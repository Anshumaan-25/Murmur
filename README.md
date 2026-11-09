# Keydown

A personal macOS dictation utility with local recognition and local text editing.

Requires macOS 26 or later and Swift command line tools. Build with `make app`, launch with `make run`, install in Applications with `make install`, and verify with `make test`. No package dependencies are needed for the basic native application.

Before granting permissions, run `bash scripts/create_signing_identity.sh` then rebuild. This creates a private project keychain. Unlock it with `security unlock-keychain .local/signing.keychain-db` or supply `KEYDOWN_SIGNING_PASSWORD` for the build. Existing identities keep their signing requirements. Without that identity, builds use ad hoc signatures and macOS may require renewed grants after a rebuild. Keep the application at the same path.

Older signing setups may have left `signing-key.pem` and `signing.p12` in `.local`. After confirming the existing keychain can sign an upgrade with the same designated requirement, remove those redundant exports and any copies you control. Treat a suspected key disclosure as a separate identity migration that requires renewed grants.

Enable microphone access when prompted. Enable Keydown in Accessibility to paste into another application. Input Monitoring enables hold-to-talk. Keydown can send a paste to a positively identified accessible field. Onboarding opens the relevant System Settings pane.

Keydown runs in the menu bar when its window is closed. Enable **Open at Login** in Keydown’s Settings to start it with your macOS session. Settings shows whether the login item is enabled or awaiting approval and links to macOS Login Items. Sleep, display sleep, and user switching pause dictation and restore the shortcuts when the session becomes active again. Start a fresh recording after an interruption.

Audio is transient by default. Recognition and editing providers are local. Model downloads require an explicit confirmation and checksum validation. No accounts or telemetry are included.

## Models and reproducible setup

The app built on this machine already bundles its verified English speech decoder and selected-text editing model. Models and engine build trees are intentionally ignored by Git. Their pinned checksums and source revisions are in `docs/MODELS.json` and `docs/ENGINES.json`.

From another checkout, run `python3 scripts/download_models.py --confirm`. Set `MURMUR_SPEECH_SOURCE` to the upstream whisper.cpp repository URL or an existing source checkout, and run `bash scripts/setup_engines.sh`. To build editing as well, set `MURMUR_TEXT_SOURCE` to the upstream llama.cpp source and `MURMUR_BUILD_EDITING=1`. Use a trusted CMake installation or set `KEYDOWN_CMAKE` to its absolute path. Packaging rebuilds helpers from clean pinned source trees and verifies the staged model bytes before signing.

A checkout without downloaded resources still compiles and uses the system speech adapter. That adapter requires language assets which macOS reports as ready; it never initiates an asset download. On this machine, locale listings did not match asset readiness, so the bundled decoder is the tested choice.

## Daily use

- Control Option Space starts or finishes dictation. The Settings page can change the toggle to Control Option D.
- With Input Monitoring enabled, hold Fn/globe, Right Option, Right Control, Right Shift, or F6 by itself. Keydown waits briefly to distinguish a hold from a key combination, then records until release or the duration cap. Set the system globe action to Do Nothing to avoid the emoji picker.
- Escape cancels a live session. Control Option V sends a paste for the most recent result when Keydown can verify the destination.
- Select text and press Control Option R to dictate an editing request. Common casing, tone, and shortening edits are deterministic. Other requests can produce a local suggestion. Use **Review Suggested Edit** to inspect it before copying and pasting it yourself.
- Hands-free mode ends toggle dictation after speech followed by silence. The duration cap applies in every mode.
- For changed or opaque targets, choose **Copy Previous Text** to copy the result yourself. Protected fields block delivery. A sent paste is unconfirmed because the destination controls when it reads the shared clipboard. Keydown preserves a newer clipboard item when it observes that ownership changed.
- The indicator distinguishes microphone startup from listening; wait for Listening before speaking. The menu bar also shows recording state. Settings offers **Preview indicator** and **Reset indicator position** without using the microphone. After sleep, start a fresh session; recording never resumes automatically.
- **Review Previous Text** and history's review action compare recognition with the editable result. Changed passages are highlighted; they are not a factual-verification guarantee. Copy is explicit. During recognition, finish or cancel the active job before starting another.
- Choose **Dictate prose**, **Exact text**, or **Follow app preference** in Settings. Exact text skips automatic formatting. In Exact text, an entire utterance such as “spell A B hyphen zero zero seven” produces `AB-007`; unrecognized spelling phrases stay literal.
- **Practice dictation** opens a scratch window. Keep it focused while using the shortcut, or use its Start / stop button. Practice results remain in that window, bypass history and cross-app paste, and clear when it closes. Copy and saving a vocabulary hint remain deliberate actions.

The hub contains history, vocabulary, spoken expansions, app styles, and settings. History keeps recognized text, cleaned text, and the delivery outcome. A queued paste does not count as confirmed insertion. The audio-retention switch is off by default. Optional automatic cleanup uses the installed on-device system model after passing the bundled quality and timing suite. In Settings, choose Validate local cleanup, then enable the qualified option. Qualification expires after an OS/rule/fixture change or seven days. An 800 ms deadline and a narrow capitalization check fall back to rules. Ambiguous correction phrases remain literal. Say “actually make that” to request a correction.

Run `bash scripts/checkpoint.sh` for the complete build gate. `bash scripts/demo.sh` builds and verifies without activating the microphone. The remaining permission-gated acceptance steps are in `docs/MANUAL_TESTS.md`. Benchmark values and their limits are in `docs/BENCHMARK.json`.


## Input behavior and diagnostics

Destination categories are inferred locally in Follow app preference mode. Code editors and terminals preserve syntax by default; Dictate prose explicitly overrides that inference. Existing preferences migrate field by field. The optional system-dictation provider requires its separate Speech Recognition grant; Automatic uses the bundled local decoder whenever available. To use a custom executable, reselect it and approve its bytes in Settings. The executable receives raw microphone audio and runs with your user's permissions. System providers and the packaged decoder accept vocabulary hints. The packaged decoder receives bounded hints and audio through a versioned private input stream, never vocabulary in command arguments or environment variables. Custom decoders do not receive hints. Regional English selections use the same English model and do not imply a separate accent model.

The setup script derives a compact speech model locally from the checksum-verified original, using the pinned engine revision. `docs/SPEECH_VARIANT.json` records both digests; no additional model download is involved. The compact variant is selected after the comparison in `docs/SPEECH_COMPARISON.json`.

`python3 scripts/compare_engines.py` repeats the bounded local engine comparison. `bash scripts/native_checks.sh` verifies native controls, undo/redo, Unicode, clipboard restoration and the nonactivating panel without microphone access. Add `--audio tests/audio/ten-seconds.wav` for synthetic-input pipeline timing, and `--with-cleanup` for the qualified optional model. Generate those synthetic clips with `make bench` first. These checks use an app-owned text view; external applications remain covered by the permission-gated integration script and manual checks.

Settings shows the build version and source identifier, and offers a metadata-only diagnostic export. Indicator draw dispatch is distinct from actual on-screen visibility. Diagnostics contain bounded in-memory session events and timings, not audio, transcripts or clipboard contents.

For a text-sensitive evaluation of your own explicitly chosen corpus, use `scripts/evaluate_corpus.py --help`. It reports recognition and formatting separately, including exact protected facts. Text is omitted unless `--include-text` is chosen. Synthetic clips are useful regressions but cannot establish your accent accuracy or real microphone performance. See `docs/PRODUCT_POLISH.md` for the implementation and qualification boundaries.
