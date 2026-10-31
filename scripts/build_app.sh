#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Murmur
app_path="$PWD/.build/Murmur.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
bin_path="$(swift build -c release --show-bin-path)"
cp "$bin_path/Murmur" "$app_path/Contents/MacOS/Murmur"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Murmur</string>
<key>CFBundleIdentifier</key><string>local.murmur.dictation</string>
<key>CFBundleName</key><string>Murmur</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSMicrophoneUsageDescription</key><string>Murmur records your voice only when you start dictation.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Murmur recognizes speech using installed on-device resources.</string>
</dict></plist>
PLIST
if [ -f .local/speech-build/bin/whisper-cli ] && [ -f models/ggml-small.en.bin ]; then
  cp -p .local/speech-build/bin/whisper-cli "$app_path/Contents/Resources/speech-decode"
  if [ ! "$app_path/Contents/Resources/speech-model.bin" -nt models/ggml-small.en.bin ]; then
    cp -p models/ggml-small.en.bin "$app_path/Contents/Resources/speech-model.bin"
  fi
  cp .local/vendor/speech-engine/LICENSE "$app_path/Contents/Resources/SpeechEngine-LICENSE.txt"
fi
if [ -f .local/signing.keychain-db ]; then
  if [ -f "$app_path/Contents/Resources/speech-decode" ]; then codesign --force --keychain "$PWD/.local/signing.keychain-db" --sign 'Murmur Local Development' "$app_path/Contents/Resources/speech-decode"; fi
  codesign --force --keychain "$PWD/.local/signing.keychain-db" --sign 'Murmur Local Development' "$app_path"
else
  codesign --force --sign - "$app_path"
fi
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
