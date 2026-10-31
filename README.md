# Murmur

A personal macOS dictation utility with local recognition and local text editing.

Requires macOS 26 or later and Swift command line tools. Build with `make app`, launch with `make run`, and verify with `make test`. No package dependencies are needed for the basic native application.

Before granting permissions, run `bash scripts/create_signing_identity.sh` then rebuild. This creates a private project keychain rather than using the login keychain. Without that identity, builds use ad hoc signatures and macOS may require renewed grants after a rebuild. Keep the application at the same path.

Enable microphone access when prompted. Enable Murmur in Accessibility to paste into another application. Input Monitoring is optional for the globe/function hold shortcut. Onboarding opens the relevant System Settings pane. Enable launch at login from the hub if desired.

Audio is transient by default. Recognition and editing providers are local. Model downloads require an explicit confirmation and checksum validation. No accounts or telemetry are included.
