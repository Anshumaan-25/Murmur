# Pause media before dictation

The default-on “Pause current media before dictation” setting sends a dedicated Pause to the macOS Now Playing session when a dictation gesture is accepted. Hold, toggle, selected-text edits and practice share this path. Playback stays paused after completion, cancellation or failure. It never sends Play or a play/pause toggle, changes output volume, reads song/track metadata, or launches a player.

A solo hold key-down starts a bounded, in-memory pre-roll while the shortcut is verified. A short tap or chord discards it. Accepting the gesture requests pause while capture proceeds. Release flushes the accepted recording; Escape and suspension discard it. Missing microphone permission, invalid targets, busy sessions and suspension do not request pause. The opt-out persists in preferences.

## Compatibility and limits

The small adapter dynamically resolves MRMediaRemoteSendCommand from the system MediaRemote framework and sends command 1 (Pause). This is a private macOS compatibility API, not an App Store/public API guarantee. No framework is bundled and no identity/entitlement spoofing or player-state read workaround is used. If loading or dispatch fails, recording remains available and diagnostics record `unavailable`. A successful request is `requested_unconfirmed`, never proof that every output stopped. Settings explains the limitation.

macOS targets its current media session. Spotify, Apple Music and browser media using Now Playing can participate. Multiple simultaneous players, apps ignoring media controls, games, calls and arbitrary sound output are not guaranteed to pause. Capture can include playback audible before the player responds. Audio that starts or resumes later in a recording is not continually policed. Media remains under the user's manual control.

The reported Spotify/Bluetooth volume and distortion change has not been physically reproduced. There are no output-volume writes in this feature or the capture path. Bluetooth microphone activation can change playback mode/quality; that is a possible explanation only when the Bluetooth device is also the input. Requesting pause can reduce competing playback.

## Verification

Unit checks cover default-on preference migration and opt-out round trips. Native fixtures exercise pause dispatch, immediate capture startup, cancellation before startup, release during preparation, permission denial, and suspension.

The actual production pause adapter was compiled into an isolated probe. On the user's running Spotify session its dispatch returned true and Spotify's Playback menu changed from Pause to Play. No microphone was opened, no volume was changed, and playback was left paused. This is one real-player integration check, not certification of every player.

Manual acceptance: play Spotify, Music and a browser video separately, use hold and toggle, observe whether and when playback pauses, and verify it stays paused after stop/cancel. Repeat starting already paused (nothing should start), rapid hold/release, permission denial, sleep, headphone/speaker routes, and disabling the setting. With two players, record the single-session limitation. Check output volume and capture quality on the actual Bluetooth device without treating the playback symptom as a proven hardware diagnosis.

API references: Apple’s external-player event and Bluetooth audio documentation, plus independently published MediaRemote command definitions. Reference URLs and investigation evidence are in the local implementation notes. No third-party runtime dependency was added.

A synthetic native-format tap checks pre-roll retention and resampler draining through a release inside an input packet. Physical player latency and Bluetooth routing require a hardware check.
