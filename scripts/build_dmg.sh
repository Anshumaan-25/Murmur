#!/bin/bash
# Build the complete offline Apple silicon beta using the local project identity.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 022
[[ "$(uname -m)" == arm64 ]] || { echo 'Build this release on Apple silicon.' >&2; exit 1; }
mkdir -p artifacts/releases
stage="$(mktemp -d "$PWD/artifacts/releases/.pack.XXXXXX")"
cleanup() {
  if mount | grep -Fq " on $stage/mount ("; then
    hdiutil detach "$stage/mount" || { echo "Retained mounted stage: $stage" >&2; return; }
  fi
  rm -rf -- "$stage"
}
trap cleanup EXIT
mkdir "$stage/image" "$stage/mount" "$stage/result"
KEYDOWN_ADHOC=0 KEYDOWN_DISTRIBUTION=1 KEYDOWN_APP_OUTPUT="$stage/image/Keydown.app" bash scripts/build_app.sh
app="$stage/image/Keydown.app"
resources="$app/Contents/Resources"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
name="Keydown-$version-beta.1-arm64"
out="$PWD/artifacts/releases/$name"
if [[ -e "$out" ]]; then echo "Release already exists: $out" >&2; exit 1; fi
for file in speech-model.bin speech-protocol.json editing-model.gguf SpeechModel-LICENSE.txt SpeechEngine-LICENSE.txt EditingModel-LICENSE.txt TextEngine-LICENSE.txt; do
  test -s "$resources/$file" || { echo "Missing $file" >&2; exit 1; }
done
python3 - "$resources" <<'PY'
import json, sys
from pathlib import Path
assets = json.loads((Path(sys.argv[1]) / "build-info.json").read_text())["assets"]
expected = json.loads(Path("docs/SPEECH_VARIANT.json").read_text())["output_sha256"]
if assets["speech-model.bin"] != expected:
    raise SystemExit("Release requires the verified Q5 speech model.")
PY
for binary in "$app/Contents/MacOS/Keydown" "$resources/speech-decode" "$resources/text-complete"; do
  test -x "$binary"
  lipo -verify_arch arm64 "$binary"
  codesign --verify --strict "$binary"
done
# Signing runs under a private umask. Public bundle files must work for other accounts.
chmod -R a+rX "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$stage/image/Applications"
hdiutil create -quiet -volname Keydown -fs HFS+ -format UDZO -srcfolder "$stage/image" "$stage/result/$name.dmg"
hdiutil verify -quiet "$stage/result/$name.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$stage/mount" "$stage/result/$name.dmg"
test "$(readlink "$stage/mount/Applications")" = /Applications
codesign --verify --deep --strict "$stage/mount/Keydown.app"
hdiutil detach "$stage/mount"
(cd "$stage/result" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256")
# rename fails rather than nesting the result if another builder published first.
python3 -c 'import os,sys; os.rename(sys.argv[1], sys.argv[2])' "$stage/result" "$out"
printf 'Verified local beta: %s/%s.dmg\n' "$out" "$name"
