#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Murmur
app_path="$PWD/.build/Murmur.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
bin_path="$(swift build -c release --show-bin-path)"
cp "$bin_path/Murmur" "$app_path/Contents/MacOS/Murmur"
swift scripts/create_icon.swift .build/Murmur.iconset
iconutil -c icns .build/Murmur.iconset -o "$app_path/Contents/Resources/Murmur.icns"
cp tests/golden/cases.json "$app_path/Contents/Resources/cleanup-cases.json"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Murmur</string>
<key>CFBundleIdentifier</key><string>local.murmur.dictation</string>
<key>CFBundleName</key><string>Murmur</string>
<key>CFBundleIconFile</key><string>Murmur</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSMicrophoneUsageDescription</key><string>Murmur records your voice only when you start dictation.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Murmur recognizes speech using installed on-device resources.</string>
</dict></plist>
PLIST
speech_model="models/ggml-small.en.bin"
if [ -f models/ggml-small.en-q5_1.bin ]; then
  python3 -c 'import hashlib,json,pathlib; p=pathlib.Path("models/ggml-small.en-q5_1.bin"); s=json.load(open("docs/SPEECH_VARIANT.json")); h=hashlib.file_digest(p.open("rb"),"sha256").hexdigest() if hasattr(hashlib,"file_digest") else hashlib.sha256(p.read_bytes()).hexdigest(); assert h==s["output_sha256"], "Derived speech model checksum mismatch"'
  speech_model="models/ggml-small.en-q5_1.bin"
fi
if [ -f .local/speech-build/bin/whisper-cli ] && [ -f "$speech_model" ]; then
  cp -p .local/speech-build/bin/whisper-cli "$app_path/Contents/Resources/speech-decode"
  if [ ! -f "$app_path/Contents/Resources/speech-model.bin" ] || [ "$(stat -f%z "$speech_model")" != "$(stat -f%z "$app_path/Contents/Resources/speech-model.bin")" ] || [ "$speech_model" -nt "$app_path/Contents/Resources/speech-model.bin" ]; then
    cp -p "$speech_model" "$app_path/Contents/Resources/speech-model.bin"
  fi
  cp .local/vendor/speech-engine/LICENSE "$app_path/Contents/Resources/SpeechEngine-LICENSE.txt"
fi
if [ -f .local/text-build/bin/llama-completion ] && [ -f models/qwen2.5-1.5b-instruct-q4_k_m.gguf ]; then
  cp -p .local/text-build/bin/llama-completion "$app_path/Contents/Resources/text-complete"
  if [ ! -f "$app_path/Contents/Resources/editing-model.gguf" ] || [ models/qwen2.5-1.5b-instruct-q4_k_m.gguf -nt "$app_path/Contents/Resources/editing-model.gguf" ]; then
    cp -p models/qwen2.5-1.5b-instruct-q4_k_m.gguf "$app_path/Contents/Resources/editing-model.gguf"
  fi
  cp .local/vendor/text-engine/LICENSE "$app_path/Contents/Resources/TextEngine-LICENSE.txt"
  if [ -f .local/model-license.txt ]; then cp .local/model-license.txt "$app_path/Contents/Resources/EditingModel-LICENSE.txt"; fi
fi
if [ -f .local/signing.keychain-db ]; then
  security unlock-keychain -p murmur-local "$PWD/.local/signing.keychain-db"
  if [ -f "$app_path/Contents/Resources/speech-decode" ]; then codesign --force --keychain "$PWD/.local/signing.keychain-db" --sign 'Murmur Local Development' "$app_path/Contents/Resources/speech-decode"; fi
  if [ -f "$app_path/Contents/Resources/text-complete" ]; then codesign --force --keychain "$PWD/.local/signing.keychain-db" --sign 'Murmur Local Development' "$app_path/Contents/Resources/text-complete"; fi
  codesign --force --keychain "$PWD/.local/signing.keychain-db" --sign 'Murmur Local Development' "$app_path"
else
  codesign --force --sign - "$app_path"
fi
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
