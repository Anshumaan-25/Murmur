# Keydown signing recovery

The signer reads its generated project keychain password from the macOS login Keychain. After restarting the Mac, sign in to the same macOS account and run `bash scripts/create_signing_identity.sh` to check it. The project keychain starts locked, unlocks for the signing operation, and locks again afterward. If the login Keychain is locked, unlock it through Keychain Access. A missing or incorrect item stops the build before the app is staged. The generated password has no expiry set by the script. The certificate has its own expiration date.

Record the public SHA-1 certificate fingerprint separately from any backup. Find it in `.local/code-signing/certificate.sha1` and compare it with the installed app's designated requirement:

```sh
codesign -d -r- /Applications/Keydown.app
```

## Create an encrypted portable backup

Use this procedure only with approval to create a new copy of the private key. Use the original certificate and its verified legacy PEM key. Choose a strong, unique passphrase in a password manager. Run the following from the repository root, with the destination set to a new file on encrypted backup storage. OpenSSL prompts for the passphrase twice with input hidden. Store the passphrase separately from the backup and the public fingerprint.

```sh
umask 077
(
  set -C
  /usr/bin/openssl pkcs12 -export \
    -inkey .local/signing-key.pem -in .local/signing-cert.pem \
    -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256 \
    > /Volumes/EncryptedBackup/Keydown-signing.p12
)
```

Keep the existing recovery copies until the portable backup has passed a restore and signing probe in a separate checkout. The managed private key is imported as non-exportable. Copying its keychain database alone does not carry the login Keychain credential to a new Mac.

## Restore the original identity

On a fresh checkout for an existing installation, use the restore command below before running the setup script without arguments. With no local signing files, the no-argument setup creates a different identity. The installer will refuse to replace an existing signed app if the new identity does not meet its signing requirement.

1. Use a separate checkout on the target Mac for a restore drill. For an in-place recovery, stop any builds and move the existing `.local/code-signing` directory to a new preserved path. Keep its original login Keychain item as well. Restore creates a new item with a different account name. Keep the old files until the new signer passes verification.
2. Sign in to the target macOS account, then run the command below from the checkout. Supply the independently recorded fingerprint. Enter the portable backup passphrase locally at the hidden prompt.
3. Run the setup script again with no arguments to verify the saved credential can unlock the project keychain and sign. Build the app. On the same Mac, the installer checks the new bundle against the currently installed app's requirement. On a new Mac, macOS may require fresh permissions.

```sh
bash scripts/create_signing_identity.sh \
  --restore-pkcs12 /Volumes/EncryptedBackup/Keydown-signing.p12 \
  --fingerprint YOUR_RECORDED_SHA1_FINGERPRINT
bash scripts/create_signing_identity.sh
make app
```

If only the original local keychain and PEM exports are available, use `bash scripts/create_signing_identity.sh --recover-legacy` in step 2. That path checks the legacy certificate and signs a probe with the recovered private key. The original keychain password is unnecessary.

If the certificate expires, stop before replacing the app. The scripts do not rotate the certificate automatically. Plan a separate signing migration and review the resulting macOS permission changes.
