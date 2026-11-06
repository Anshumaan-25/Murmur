#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_binary="$PWD/.build/Keydown.app/Contents/MacOS/Keydown"
status_json="$("$app_binary" --diagnostics)"
if ! python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["accessibility_authorized"] else 1)' <<< "$status_json"; then
  printf 'SKIPPED: Enable Keydown in System Settings > Privacy & Security > Accessibility.\n'
  exit 77
fi
osascript <<'APPLESCRIPT'
tell application "TextEdit"
  make new document with properties {text:"Keydown integration: "}
  activate
end tell
APPLESCRIPT
sleep 1
"$app_binary" --test-insert 'Verified local insertion.'
osascript <<'APPLESCRIPT'
tell application "TextEdit"
  if text of front document does not contain "Verified local insertion." then error "Insertion not observed"
  close front document saving no
end tell
APPLESCRIPT
printf 'TextEdit integration passed.\n'
