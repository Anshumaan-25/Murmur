#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make test
make app
.build/Keydown.app/Contents/MacOS/Keydown --diagnostics
printf 'Launch with make run. Use Control Option Space in an editable field.\n'
