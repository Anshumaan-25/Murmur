#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make test
make app
python3 scripts/cleanroom_check.py
codesign --verify --deep --strict .build/Murmur.app
