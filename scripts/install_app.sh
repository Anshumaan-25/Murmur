#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
built_app=.build/Keydown.app
installed_app=/Applications/Keydown.app
legacy_app=/Applications/Murmur.app
codesign --verify --deep --strict "$built_app"
for app in "$installed_app" "$legacy_app"; do
  if [ -e "$app" ] || [ -L "$app" ]; then
    if [ -L "$app" ] || [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" != local.murmur.dictation ]; then
      printf 'Refusing to replace an unrelated app at %s\n' "$app" >&2
      exit 1
    fi
  fi
done
python3 - <<'PY'
import os, signal, subprocess, time
executables = (
    '/Applications/Keydown.app/Contents/MacOS/Keydown',
    '/Applications/Murmur.app/Contents/MacOS/Murmur',
)
for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) != 2 or not any(parts[1] == executable or parts[1].startswith(executable + ' ') for executable in executables):
        continue
    pid = int(parts[0])
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try: os.kill(pid, 0)
        except ProcessLookupError: break
        time.sleep(0.05)
    else: raise SystemExit('The running app did not quit. Installation stopped.')
PY
ditto "$built_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
if [ -d "$legacy_app" ]; then
  mkdir -p .local
  backup_dir=$(mktemp -d "$PWD/.local/previous-install.XXXXXX")
  mv "$legacy_app" "$backup_dir/Murmur.bundle"
  printf 'Archived the previous app at %s/Murmur.bundle\n' "$backup_dir"
fi
open "$installed_app" --args --show
printf 'Installed and opened %s\n' "$installed_app"
