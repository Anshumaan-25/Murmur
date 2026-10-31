# Verification record

Completed on this Apple M5 MacBook Air with 16 GiB RAM, macOS 27.0.1, and Swift 6.4.

## Passing automated checks

- 89 compiled Swift checks, including 40 text-pipeline fixtures.
- Actual SQLite save/search/retention and app-style/vocabulary/expansion operations.
- Named-pasteboard round trips with multiple items and custom binary data, plus protection of a newer clipboard owner.
- Cancellation of a real child process, stale identities, duration/silence boundaries, terminal return intent, and deterministic editing requests.
- Release app packaging and strict signature verification of the app and its bundled decoders.
- Fresh Git checkout: `make test`, `make app`, and `make run` completed successfully. That checkout contains no ignored model files; downloaded resources remain an explicit setup step.
- Clean-room check passed. Artificial fixtures separately verified that both long textual overlap and a bare hostname cause failure, without printing matched content.
- The bundled recognizer returned nonempty text with all network operations denied, from a working directory outside the project. This validates local model/resource use rather than requiring a device-wide Wi-Fi change.

## Measured performance

The initial short-clip comparison used three synthetic Samantha-voice recordings and measured a 0.459-second median including decoder process startup, with 2.1% normalized word error. Five full ten-second PCM inputs measured a 0.481-second median for the development decoder. Two packaged-decoder runs outside the project took 0.507 and 0.448 seconds.

The first explicitly network-denied packaged run took 4.851 seconds. Three subsequent network-denied runs took 0.459, 0.436 and 0.445 seconds. Cold initialization or cache behavior can therefore matter; these measurements do not establish a universal latency bound.

A local four-bit 1.5B cleanup example took 5.389 seconds cold, so automatic model cleanup stays disabled. A separate requested selected-text edit took 5.163 seconds. General model edits are slower and should be reviewed for fidelity.

An idle sample with the hub open showed 0.0% CPU and 102,832 KiB resident memory, approximately 100.4 MiB. This is a short observation, not an extended profiler trace. No internet sockets were visible for that app process.

## Acceptance still requiring OS access

Microphone, Accessibility and Input Monitoring have not been granted to the signed app. The TextEdit automation returned its documented skipped status. Consequently, microphone capture quality, key-down-to-visible feedback, release-to-insertion latency, physical Fn behavior, fullscreen focus, paste reliability across the requested applications, and native undo have not been validated end to end. Decoder timing must not be presented as release-to-insertion timing.

Open Murmur → Settings and enable Microphone. In System Settings → Privacy & Security → Accessibility, enable the built Murmur app. Input Monitoring is needed only for holding Fn/globe. The registered toggle works without it. Set Keyboard → Press globe key to Do Nothing if using the hold gesture. Follow MANUAL_TESTS.md after grants; no chat confirmation is needed.

Privacy settings URL dispatch, launch-at-login registration, and per-device microphone selection are implemented but need the corresponding interactive OS checks. The system speech adapter reported installed English locales while its per-module readiness check rejected the assets; the checksum-verified bundled recognizer is the tested default. Other speech-engine candidates were not benchmarked once this option met the decoder budget within the bounded comparison.

No reference application was launched, changed, instrumented, or used as a runtime test target during this build. Its application data was not accessed. The specification bridge remained closed after Phase B, except for the automated clean-room scanner's permitted reads.

Machine-readable results are in VERIFICATION.json and BENCHMARK.json. Models, compiler outputs, downloaded dependency trees, private signing material and synthetic audio files remain ignored by Git.
