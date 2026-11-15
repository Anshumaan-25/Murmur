#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" = 0 ] && [ -d .local/code-signing ]; then
  exec /usr/bin/python3 scripts/project_signing.py check
fi
exec /usr/bin/python3 scripts/project_signing.py setup "$@"
