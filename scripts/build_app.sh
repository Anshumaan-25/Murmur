#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${KEYDOWN_ADHOC:-0}" != 1 ]; then
  /usr/bin/python3 scripts/project_signing.py check
fi
mkdir -p .build
stage="$(mktemp -d "$PWD/.build/keydown-stage.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
app_path="$stage/Keydown.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
swift build --scratch-path "$stage/swift" -c release --product Keydown
bin_path="$(swift build --scratch-path "$stage/swift" -c release --show-bin-path)"
cp "$bin_path/Keydown" "$app_path/Contents/MacOS/Keydown"
swift scripts/create_icon.swift "$stage/Keydown.iconset"
iconutil -c icns "$stage/Keydown.iconset" -o "$app_path/Contents/Resources/Keydown.icns"
cp tests/golden/cases.json "$app_path/Contents/Resources/cleanup-cases.json"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Keydown</string>
<key>CFBundleIdentifier</key><string>local.murmur.dictation</string>
<key>CFBundleName</key><string>Keydown</string>
<key>CFBundleDisplayName</key><string>Keydown</string>
<key>CFBundleIconFile</key><string>Keydown.icns</string>
<key>CFBundleShortVersionString</key><string>0.2.11</string>
<key>CFBundleVersion</key><string>13</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSMicrophoneUsageDescription</key><string>Keydown records your voice only when you start dictation.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Keydown recognizes speech using installed on-device resources.</string>
</dict></plist>
PLIST
python3 scripts/stage_engines.py --resources "$app_path/Contents/Resources"
if [ "${KEYDOWN_ADHOC:-0}" != 1 ]; then
  /usr/bin/python3 scripts/project_signing.py sign "$app_path"
else
  for helper in speech-decode text-complete; do
    if [ -f "$app_path/Contents/Resources/$helper" ]; then codesign --force --sign - "$app_path/Contents/Resources/$helper"; fi
  done
  python3 scripts/build_manifest.py "$app_path/Contents/Resources"
  codesign --force --sign - "$app_path"
fi
codesign --verify --deep --strict "$app_path"
python3 scripts/replace_bundle.py "$app_path" "$PWD/.build/Keydown.app"
printf 'Built %s\n' "$PWD/.build/Keydown.app"
