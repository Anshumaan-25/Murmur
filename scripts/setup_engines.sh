#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/vendor
if ! command -v cmake >/dev/null && [ ! -x .local/buildenv/bin/cmake ]; then
  python3 -m venv .local/buildenv
  .local/buildenv/bin/pip install cmake==4.4.4
fi
build_tool="$(command -v cmake || true)"
if [ -z "$build_tool" ]; then build_tool="$PWD/.local/buildenv/bin/cmake"; fi
if [ ! -d .local/vendor/speech-engine ]; then
  : "${MURMUR_SPEECH_SOURCE:?Set this to the upstream speech engine source URL or a local source directory}"
  git clone "$MURMUR_SPEECH_SOURCE" .local/vendor/speech-engine
fi
speech_revision="$(python3 -c 'import json; print(json.load(open("docs/ENGINES.json"))["speech"])')"
if [ "$(git -C .local/vendor/speech-engine rev-parse HEAD)" != "$speech_revision" ]; then
  git -C .local/vendor/speech-engine fetch --depth 1 origin "$speech_revision"
  git -C .local/vendor/speech-engine switch --detach "$speech_revision"
fi
"$build_tool" -S .local/vendor/speech-engine -B .local/speech-build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF
"$build_tool" --build .local/speech-build --target whisper-cli -j 6
if [ -f models/ggml-small.en.bin ]; then
  "$build_tool" --build .local/speech-build --target whisper-quantize -j 6
  python3 scripts/quantize_speech.py
fi
if [ "${MURMUR_BUILD_EDITING:-0}" = 1 ]; then
  if [ ! -d .local/vendor/text-engine ]; then
    : "${MURMUR_TEXT_SOURCE:?Set this to the upstream text engine source URL or a local source directory}"
    git clone "$MURMUR_TEXT_SOURCE" .local/vendor/text-engine
  fi
  text_revision="$(python3 -c 'import json; print(json.load(open("docs/ENGINES.json"))["editing"])')"
  if [ "$(git -C .local/vendor/text-engine rev-parse HEAD)" != "$text_revision" ]; then
    git -C .local/vendor/text-engine fetch --depth 1 origin "$text_revision"
    git -C .local/vendor/text-engine switch --detach "$text_revision"
  fi
  "$build_tool" -S .local/vendor/text-engine -B .local/text-build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF
  "$build_tool" --build .local/text-build --target llama-completion -j 6
fi
