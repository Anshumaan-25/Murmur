#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
codesign --verify --deep --strict .build/Murmur.app
python3 - <<'PY'
import os, signal, subprocess, time
executable = '/Applications/Murmur.app/Contents/MacOS/Murmur'
for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) != 2 or not (parts[1] == executable or parts[1].startswith(executable + ' ')):
        continue
    pid = int(parts[0])
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try: os.kill(pid, 0)
        except ProcessLookupError: break
        time.sleep(0.05)
    else: raise SystemExit('Murmur did not quit; installation stopped.')
PY
ditto .build/Murmur.app /Applications/Murmur.app
codesign --verify --deep --strict /Applications/Murmur.app
open /Applications/Murmur.app --args --show
printf 'Installed and opened /Applications/Murmur.app\n'
