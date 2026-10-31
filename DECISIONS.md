# Decisions

- D01: Native Swift with AppKit and SwiftUI, packaged through SwiftPM and a shell bundler. The installed command line SDK is sufficient; a full IDE install is unnecessary.
- D02: Target this Apple M5 computer with 16 GiB memory on macOS 27.0.1. Swift 6.4 and the macOS 27 SDK are present. Node, a package manager, speech synthesis, SQLite, and REA CLI are available. No global installation is needed.
- D03: Recognition is interchangeable. Probe system on-device recognition and asset availability before requesting a downloadable decoder. Never silently download a language asset or fall back to network recognition.
- D04: Rules are the default cleanup. Optional local language generation must satisfy a deadline and conservative output validation. A missing model never blocks ordinary rule cleanup.
- D05: Use a project-local signing keychain if available. Do not modify the login keychain. Ad hoc signing is an explicitly documented fallback until a stable identity is created.
- D06: The user's accompanying request authorizes the additional milestones. Record the intermediate checkpoint results, then continue through dictionary, styles, hands-free capture, selected-text editing, and the hub.
- D07: Inspect only the behavioral specification after its creation. A checker alone can consult the analysis directory to detect accidental overlap.
- D08: Prefer one-process native integration. Native audio, pasteboard, global shortcuts, and Accessibility do not need an IPC helper in this app.
- D09: The command line SDK lacks XCTest. Use a compiled standalone Swift verification executable driven by `make test`, rather than installing an IDE or weakening coverage.
- D10: System English speech assets and a local system language model are already installed. Microphone is undetermined; Accessibility and monitoring are not granted. These are manual OS grants, not build blockers.
- D11: This SDK ships SwiftUI declarations that depend on absent macro plugins. Use native AppKit views instead of requiring a full IDE or switching to a web runtime. The user experience and native architecture remain intact.
- D12: Downloaded a checksum-pinned English small-class speech model and a 1.5B four-bit instruction model after authorization. The downloaded decoder reads PCM from standard input; no microphone file is required. System speech reports installed locales but rejects the requested asset state, so the bundled decoder is the initial reliable default.
- D13: Build optional decoder tools in the project directory. License notices accompany bundled executable resources. The application makes no inference-service requests.
