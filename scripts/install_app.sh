#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
built_app=.build/Keydown.app
installed_app=/Applications/Keydown.app
legacy_app=/Applications/Murmur.app
test ! -L "$built_app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")" = local.murmur.dictation
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$built_app/Contents/Info.plist")" = Keydown
codesign --verify --deep --strict "$built_app"
for app in "$installed_app" "$legacy_app"; do
  if [ -e "$app" ] || [ -L "$app" ]; then
    if [ -L "$app" ] || [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" != local.murmur.dictation ]; then
      printf 'Refusing to replace an unrelated app at %s\n' "$app" >&2
      exit 1
    fi
  fi
done
stage="$(mktemp -d /Applications/.keydown-stage.XXXXXX)"
staged_app="$stage/Keydown.app"
published=0
stopped=0
keep_backup=0
cleanup() {
  if [ "$published" = 1 ]; then
    if [ -d "$staged_app" ]; then
      python3 scripts/replace_bundle.py "$staged_app" "$installed_app" || keep_backup=1
    else
      mv "$installed_app" "$staged_app" || keep_backup=1
    fi
  fi
  if [ "$stopped" = 1 ] && [ "$keep_backup" = 0 ]; then
    if [ -d "$installed_app" ]; then open -g "$installed_app" || true
    elif [ -d "$legacy_app" ]; then open -g "$legacy_app" || true; fi
  fi
  if [ "$keep_backup" = 0 ]; then rm -rf -- "$stage"; else printf 'Recovery files: %s\n' "$stage" >&2; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
/usr/bin/ditto "$built_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"
for existing in "$installed_app" "$legacy_app"; do
  if [ -d "$existing" ]; then
    details="$(codesign -d --verbose=2 "$existing" 2>&1)"
    if ! /usr/bin/grep -qx 'Signature=adhoc' <<< "$details"; then
      requirement="$(codesign -d -r- "$existing" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
      test -n "$requirement"
      codesign --verify --strict -R="$requirement" "$staged_app"
    fi
  fi
done
xcrun swiftc scripts/quit_installed_app.swift -o "$stage/quit-installed-app"
"$stage/quit-installed-app" local.murmur.dictation 30 \
  "$installed_app/Contents/MacOS/Keydown" "$legacy_app/Contents/MacOS/Murmur"
stopped=1
python3 scripts/replace_bundle.py "$staged_app" "$installed_app"
published=1
codesign --verify --deep --strict "$installed_app"
open -g "$installed_app" --args --background
published=0
stopped=0
if [ -d "$legacy_app" ]; then
  mkdir -p .local
  backup_dir=$(mktemp -d "$PWD/.local/previous-install.XXXXXX")
  mv "$legacy_app" "$backup_dir/Murmur.bundle"
  printf 'Archived the previous app at %s/Murmur.bundle\n' "$backup_dir"
fi
printf 'Installed and started %s\n' "$installed_app"
