#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make test
bash scripts/native_checks.sh
python3 scripts/cleanroom_check.py
codesign --verify --deep --strict .build/Keydown.app
