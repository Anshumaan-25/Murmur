#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make test
make app
printf 'Launch with: make run\n'
