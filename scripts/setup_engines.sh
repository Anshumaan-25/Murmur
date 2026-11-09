#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/vendor
prepare() {
  local kind="$1" directory="$2" source="$3" revision
  revision="$(python3 -c 'import json,sys; print(json.load(open("docs/ENGINES.json"))[sys.argv[1]])' "$kind")"
  if [ ! -d "$directory" ]; then
    : "${source:?Set the upstream source URL or a local checkout}"
    git clone --no-checkout -- "$source" "$directory"
    if ! git -C "$directory" cat-file -e "$revision^{commit}"; then
      git -C "$directory" fetch --depth 1 origin "$revision"
    fi
    git -C "$directory" switch --detach "$revision"
  fi
  python3 scripts/stage_engines.py --prepare "$kind"
}
prepare speech .local/vendor/speech-engine "${MURMUR_SPEECH_SOURCE:-}"
if [ -f models/ggml-small.en.bin ]; then python3 scripts/quantize_speech.py; fi
if [ "${MURMUR_BUILD_EDITING:-0}" = 1 ]; then
  prepare editing .local/vendor/text-engine "${MURMUR_TEXT_SOURCE:-}"
fi
