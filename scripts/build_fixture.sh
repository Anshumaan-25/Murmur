#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$PWD/.build/fixture-build"
mkdir -p .build
stage="$(mktemp -d "$PWD/.build/fixture-stage.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
fixture="$stage/Keydown Fixture.app"
swift build --scratch-path "$scratch" -c release --product Keydown -Xswiftc -DKEYDOWN_FIXTURE >&2
bin_path="$(swift build --scratch-path "$scratch" -c release --show-bin-path)"
mkdir -p "$fixture/Contents/MacOS" "$fixture/Contents/Resources"
cp "$bin_path/Keydown" "$fixture/Contents/MacOS/KeydownFixture"
cat > "$fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KeydownFixture</string>
<key>CFBundleIdentifier</key><string>local.murmur.fixture</string>
<key>CFBundleName</key><string>Keydown Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp tests/golden/cases.json "$fixture/Contents/Resources/cleanup-cases.json"
if [ -d .build/Keydown.app ]; then codesign --verify --deep --strict .build/Keydown.app; fi
for asset in speech-decode speech-model.bin speech-protocol.json build-info.json; do
    path=".build/Keydown.app/Contents/Resources/$asset"
    if [ -f "$path" ]; then cp "$path" "$fixture/Contents/Resources/$asset"; fi
done
codesign --force --sign - "$fixture" >&2
codesign --verify --deep --strict "$fixture"
python3 scripts/replace_bundle.py "$fixture" "$PWD/.build/Keydown Fixture.app"
printf '%s\n' "$PWD/.build/Keydown Fixture.app"
