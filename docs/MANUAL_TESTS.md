# Manual acceptance checks

These checks require the signed app's operating-system grants. No permission status is inferred from a unit check.

1. Launch the built app, enable microphone access, enable Accessibility, and refresh the status. Rebuild at the same location and confirm the grants remain associated with its stable signing identity.
2. Open TextEdit, click a new document, and use Control Option Space. Speak, then press the shortcut again. Confirm insertion at the original caret and undo with Command Z.
3. Repeat in Notes, a Safari textarea, a Chrome textarea, Slack, and a code editor. These applications may expose different Accessibility attributes; record copied fallbacks separately from successful insertion.
4. Put multiple items and custom rich clipboard types on the pasteboard. Dictate and verify byte-identical contents return. During the restore interval, copy new content in another app; verify Keydown leaves the new clipboard owner alone.
5. Change app, field, cursor position, or selection while recognition runs. Verify the result is copied rather than inserted into the changed target. A protected/password field must receive nothing.
6. Cancel during capture and decoding. Start another session immediately. Confirm old work cannot insert text, close the newer indicator, or overwrite the new status.
7. Grant Input Monitoring, enable the globe/function hold shortcut, and set the system globe action to Do Nothing in Keyboard settings. Confirm key release finishes capture and ordinary typing still works.
8. Exercise the indicator on a different Space and over a fullscreen app. It must not become the focused window. Drag it and relaunch to check saved docking.
9. Disable Wi-Fi after model setup. Dictate several utterances and use every local editing feature. Confirm no additional assets are requested.
10. From an installed app, enable Open at Login in Settings. Check the reported state in Keydown and macOS Login Items. On a fresh login, confirm the menu bar icon appears without a window. Open Keydown from its menu, then close the window and confirm the shortcut still works.

11. Try each physical hold-key option. Repeated key-down events must start once and release must end only the recording started by that hold. Disabling or reconfiguring a held trigger must cancel its recording. Ordinary toggle capture must survive an unrelated hold-key release.
12. In Settings, validate local cleanup and enable it only after qualification. Try spoken punctuation, instructions that should be dictated as text, names, numbers, and lists. Confirm that a slow model falls back promptly. Revalidate after OS or fixture changes.
13. Try dictation in a code editor or terminal. Exact syntax should be preserved when the option is on; ordinary prose cleanup should return when it is disabled. Confirm inferred categories and per-app styles suit your use.
14. After several real dictations, inspect this-launch timing in Settings. Record microphone-to-insertion latency separately from the app-owned synthetic fixture results.

15. With the Mac unlocked and the installed Keydown app running, run `python3 scripts/cross_app_check.py`. It builds disposable native/WebKit destinations, launches the installed app through Launch Services, and checks actual Unicode paste (plus native undo/redo). A focus change or locked session is a skip, never an instruction to bypass the protected target.
16. If a dictation is copied, read the specific reason in the indicator or its history outcome. Test missing Accessibility, a moved caret, a changed field, and a held Control/Option key independently.

17. In a custom editor with no accessible text field, keep the original app/window and cursor undisturbed while dictating. Confirm automatic paste. Repeat with a click or cursor key while recognition runs; confirm copied fallback. Input Monitoring is required for this focus-continuity path.
18. Run `/Applications/Keydown.app/Contents/MacOS/Keydown --diagnostics --check-delivery` with the intended app focused. It asks the existing GUI process to evaluate readiness and prints metadata only; `posted_input` must be false.
19. Put the Mac to sleep or switch macOS users during a disposable dictation. On return, confirm the recording has stopped, the indicator has cleared, and the interrupted text does not paste. Try the toggle and the configured hold shortcut again. Repeat while recognition is in progress and while changing the input device.
