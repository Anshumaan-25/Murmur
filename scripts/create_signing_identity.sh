#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
if [ -f .local/signing.keychain-db ]; then
  printf 'Project signing keychain already exists.\n'; exit 0
fi
umask 077
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 -subj '/CN=Murmur Local Development/' -keyout .local/signing-key.pem -out .local/signing-cert.pem -addext 'extendedKeyUsage=codeSigning' -addext 'keyUsage=digitalSignature'
openssl pkcs12 -export -out .local/signing.p12 -inkey .local/signing-key.pem -in .local/signing-cert.pem -passout pass:murmur-local
security create-keychain -p murmur-local "$PWD/.local/signing.keychain-db"
security unlock-keychain -p murmur-local "$PWD/.local/signing.keychain-db"
security import .local/signing.p12 -k "$PWD/.local/signing.keychain-db" -P murmur-local -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k murmur-local "$PWD/.local/signing.keychain-db" >/dev/null
printf 'Identity created in the project keychain. Your login keychain was not changed.\n'
