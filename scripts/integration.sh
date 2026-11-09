#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/cross_app_check.py
