#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make app
fixture="$(bash scripts/build_fixture.sh)"
"$fixture/Contents/MacOS/KeydownFixture" --native-checks "$@" | python3 -c 'import json,sys; result=json.load(sys.stdin); print(json.dumps(result,indent=2)); sys.exit(0 if result["passed"] else 1)'
