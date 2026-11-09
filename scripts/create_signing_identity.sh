#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p .local
keychain="$PWD/.local/signing.keychain-db"
if [ -f "$keychain" ]; then
  printf 'Project signing keychain already exists.\n'; exit 0
fi
if [ -z "${KEYDOWN_SIGNING_PASSWORD:-}" ]; then
  read -r -s -p "Choose a project keychain password: " KEYDOWN_SIGNING_PASSWORD
  printf '\n'
fi
: "${KEYDOWN_SIGNING_PASSWORD:?A project keychain password is required}"
stage="$(mktemp -d "${TMPDIR:-/tmp}/keydown-signing.XXXXXX")"
created=0
complete=0
cleanup() {
  rm -rf -- "$stage"
  if [ "$created" = 1 ] && [ "$complete" = 0 ]; then security delete-keychain "$keychain" || true; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
export KEYDOWN_IMPORT_PASSWORD="$(openssl rand -hex 32)"
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 -subj '/CN=Murmur Local Development/' -keyout "$stage/key.pem" -out "$stage/cert.pem" -addext 'extendedKeyUsage=codeSigning' -addext 'keyUsage=digitalSignature'
openssl pkcs12 -export -out "$stage/identity.p12" -inkey "$stage/key.pem" -in "$stage/cert.pem" -passout env:KEYDOWN_IMPORT_PASSWORD
security create-keychain -p "$KEYDOWN_SIGNING_PASSWORD" "$keychain"
created=1
security unlock-keychain -p "$KEYDOWN_SIGNING_PASSWORD" "$keychain"
security import "$stage/identity.p12" -k "$keychain" -P "$KEYDOWN_IMPORT_PASSWORD" -T /usr/bin/codesign -x
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYDOWN_SIGNING_PASSWORD" "$keychain" >/dev/null
complete=1
printf 'Identity created in the project keychain. Unlock it before building.\n'
