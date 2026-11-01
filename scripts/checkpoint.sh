#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make test
make app
python3 scripts/cleanroom_check.py
codesign --verify --deep --strict .build/Murmur.app

.build/Murmur.app/Contents/MacOS/Murmur --native-checks | python3 -c 'import json,sys; result=json.load(sys.stdin); print("Native controls:", "passed" if result["passed"] else "failed"); sys.exit(0 if result["passed"] else 1)'
