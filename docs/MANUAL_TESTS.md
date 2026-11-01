# Manual acceptance checks

These checks require the signed app's operating-system grants. No permission status is inferred from a unit check.

1. Launch the built app, enable microphone access, enable Accessibility, and refresh the status. Rebuild at the same location and confirm the grants remain associated with its stable signing identity.
2. Open TextEdit, click a new document, and use Control Option Space. Speak, then press the shortcut again. Confirm insertion at the original caret and undo with Command Z.
3. Repeat in Notes, a Safari textarea, a Chrome textarea, Slack, and a code editor. These applications may expose different Accessibility attributes; record copied fallbacks separately from successful insertion.
4. Put multiple items and custom rich clipboard types on the pasteboard. Dictate and verify byte-identical contents return. During the restore interval, copy new content in another app; verify Murmur leaves the new clipboard owner alone.
5. Change app, field, cursor position, or selection while recognition runs. Verify the result is copied rather than inserted into the changed target. A protected/password field must receive nothing.
6. Cancel during capture and decoding. Start another session immediately. Confirm old work cannot insert text, close the newer indicator, or overwrite the new status.
7. Grant Input Monitoring, enable the globe/function hold shortcut, and set the system globe action to Do Nothing in Keyboard settings. Confirm key release finishes capture and ordinary typing still works.
8. Exercise the indicator on a different Space and over a fullscreen app. It must not become the focused window. Drag it and relaunch to check saved docking.
9. Disable Wi-Fi after model setup. Dictate several utterances and use every local editing feature. Confirm no additional assets are requested.
10. Test launch-at-login registration from a stable app location. Check settings links reach the intended privacy category; macOS can route deep links to the general privacy page.

11. Try each physical hold-key option. Repeated key-down events must start once; release must end only the recording started by that hold. Disabling/reconfiguring a held trigger must release its owned session. Ordinary toggle capture must survive an unrelated hold-key release.
12. In Settings, validate local cleanup and enable it only after qualification. Try spoken punctuation, instructions that should be dictated as text, names, numbers, and lists. Confirm that a slow model falls back promptly. Revalidate after OS or fixture changes.
13. Try dictation in a code editor or terminal. Exact syntax should be preserved when the option is on; ordinary prose cleanup should return when it is disabled. Confirm inferred categories and per-app styles suit your use.
14. After several real dictations, inspect this-launch timing in Settings. Record microphone-to-insertion latency separately from the app-owned synthetic fixture results.

15. With the Mac unlocked and the installed Murmur app running, run `python3 scripts/cross_app_check.py`. It builds disposable native/WebKit destinations, launches the installed app through Launch Services, and checks actual Unicode paste (plus native undo/redo). A focus change or locked session is a skip, never an instruction to bypass the protected target.
16. If a dictation is copied, read the specific reason in the indicator or its history outcome. Test missing Accessibility, a moved caret, a changed field, and a held Control/Option key independently.

17. In a custom editor with no accessible text field, keep the original app/window and cursor undisturbed while dictating. Confirm automatic paste. Repeat with a click or cursor key while recognition runs; confirm copied fallback. Input Monitoring is required for this focus-continuity path.
18. Run `/Applications/Murmur.app/Contents/MacOS/Murmur --diagnostics --check-delivery` with the intended app focused. It asks the existing GUI process to evaluate readiness and prints metadata only; `posted_input` must be false.
