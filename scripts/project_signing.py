#!/usr/bin/env python3
"""Manage Keydown's code signing key and its login Keychain credential."""

import argparse
import ctypes
import fcntl
import getpass
import hashlib
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import warnings
from contextlib import contextmanager


ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local"
LEGACY = LOCAL / "signing.keychain-db"
STORE = LOCAL / "code-signing"
KEYCHAIN = STORE / "Keydown.keychain-db"
PIN = STORE / "certificate.sha1"
ACCOUNT_FILE = "credential-account"
SERVICE = "local.murmur.dictation.code-signing"
SECURITY = "/usr/bin/security"
CODESIGN = "/usr/bin/codesign"
OPENSSL = "/usr/bin/openssl"


class SigningError(Exception):
    pass


def run(args, *, data=None, failure, timeout=30):
    # Capture output so even an error from a command handling secrets cannot print them.
    try:
        return subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              check=True, timeout=timeout).stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise SigningError(failure) from None


def security(command, *args):
    # Feed security's command interpreter so secrets stay out of argv and shell history.
    def quote(arg):
        value = str(arg)
        if "\n" in value or "\r" in value:
            raise SigningError("Signing paths cannot contain newlines.")
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

    data = (" ".join(map(quote, (command, *args))) + "\n").encode()
    return run([SECURITY, "-i"], data=data, failure=f"Keychain operation failed: {command}.")


def login_keychain():
    path = Path.home() / "Library/Keychains/login.keychain-db"
    if not path.is_file():
        raise SigningError("The macOS login Keychain is unavailable.")
    return path


def require_unlocked_login(path):
    # A locked login keychain can otherwise open an authentication dialog during a build.
    security_api = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
    foundation = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    security_api.SecKeychainOpen.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    security_api.SecKeychainGetStatus.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    foundation.CFRelease.argtypes = [ctypes.c_void_p]
    foundation.CFRelease.restype = None
    keychain = ctypes.c_void_p()
    status = ctypes.c_uint32()
    if security_api.SecKeychainOpen(os.fsencode(path), ctypes.byref(keychain)) != 0:
        raise SigningError("Could not open the macOS login Keychain.")
    try:
        if security_api.SecKeychainGetStatus(keychain, ctypes.byref(status)) != 0:
            raise SigningError("Could not check the macOS login Keychain status.")
    finally:
        foundation.CFRelease(keychain)
    if not status.value & 1:  # kSecUnlockStateStatus
        raise SigningError("The macOS login Keychain is locked. Unlock it in Keychain Access and rerun the build.")


def saved_account():
    path = STORE / ACCOUNT_FILE
    if path.is_symlink():
        raise SigningError("The signing credential account cannot be a symbolic link.")
    return path.read_text().strip() if path.exists() else str(KEYCHAIN)


def certificate_fingerprint(cert):
    der = run([OPENSSL, "x509", "-in", cert, "-outform", "DER"],
              failure="Could not read the signing certificate.")
    return hashlib.sha1(der).hexdigest().upper()


def keychain_certificate(path, fingerprint):
    output = security("find-certificate", "-a", "-p", path)
    for pem in re.findall(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", output, flags=re.S):
        der = run([OPENSSL, "x509", "-outform", "DER"], data=pem, failure="Could not decode a Keychain certificate.")
        if hashlib.sha1(der).hexdigest().upper() == fingerprint:
            return pem
    raise SigningError("The keychain does not contain the requested signing certificate.")


def require_unexpired_certificate(pem):
    run([OPENSSL, "x509", "-noout", "-checkend", "0"], data=pem,
        failure="The pinned signing certificate has expired or could not be read.")


def codesign(path, fingerprint, *args):
    run([CODESIGN, "--force", "--keychain", KEYCHAIN, "--sign", fingerprint, *args, path],
        failure="Could not sign with the pinned Keydown identity.")


def signing_probe(directory, fingerprint):
    probe = Path(directory) / "signing-probe"
    shutil.copyfile("/usr/bin/true", probe)
    probe.chmod(0o700)
    codesign(probe, fingerprint, "--identifier", "local.murmur.dictation")
    requirement = f'identifier "local.murmur.dictation" and certificate leaf = H"{fingerprint}"'
    run([CODESIGN, "--verify", "--strict", "-R=" + requirement, probe],
        failure="The signing probe did not match the pinned certificate.")


def prepare_restore(backup, directory, passphrase, fingerprint):
    # Security.framework cannot import every PKCS#12 encryption format. Decode with
    # OpenSSL and repackage for local import without writing a plaintext private key.
    cert = directory / "restored-cert.pem"
    key = directory / "restored-key.pem"
    key_password = secrets.token_hex(32)
    run([OPENSSL, "pkcs12", "-in", backup, "-clcerts", "-nokeys", "-out", cert,
         "-passin", "stdin"], data=(passphrase + "\n").encode(),
        failure="Could not read the encrypted backup. Check the passphrase and file.")
    if certificate_fingerprint(cert) != fingerprint:
        raise SigningError("The backup certificate does not match the supplied fingerprint.")
    run([OPENSSL, "pkcs12", "-in", backup, "-nocerts", "-aes256", "-out", key,
         "-passin", "stdin", "-passout", "stdin"],
        data=(passphrase + "\n" + key_password + "\n").encode(),
        failure="Could not recover the private key from the encrypted backup.")
    return cert, key, key_password


def configure(recover, backup=None, expected=None):
    if STORE.exists() or STORE.is_symlink():
        raise SigningError("A managed Keydown signing directory already exists. Use project_signing.py check.")
    if (LEGACY.exists() or LEGACY.is_symlink()) and not recover and backup is None:
        raise SigningError("An original signing keychain exists. Use --recover-legacy to keep its signing identity.")
    LOCAL.mkdir(mode=0o700, exist_ok=True)
    if LOCAL.is_symlink():
        raise SigningError("Refusing to store the signing keychain through a symbolic link.")
    login = login_keychain()
    require_unlocked_login(login)
    STORE.mkdir(mode=0o700)
    account = f"{KEYCHAIN}:{secrets.token_hex(16)}"
    created = False
    saved = False
    complete = False
    try:
        with tempfile.TemporaryDirectory(prefix="keydown-signing-") as temp:
            directory = Path(temp)
            key_password = ""
            if backup is not None:
                if not re.fullmatch(r"[A-F0-9]{40}", expected or ""):
                    raise SigningError("Restore requires the independently recorded SHA-1 certificate fingerprint.")
                if not backup.is_file() or backup.is_symlink():
                    raise SigningError("Choose an existing PKCS#12 backup file.")
                if not sys.stdin.isatty():
                    raise SigningError("Run the restore in a terminal so the backup passphrase can be entered securely.")
                with warnings.catch_warnings():
                    warnings.simplefilter("error", getpass.GetPassWarning)
                    try:
                        backup_passphrase = getpass.getpass("Encrypted backup passphrase: ")
                    except (getpass.GetPassWarning, EOFError):
                        raise SigningError("Could not read the backup passphrase without echo.") from None
                if not backup_passphrase:
                    raise SigningError("An encrypted backup passphrase is required.")
                cert, key, key_password = prepare_restore(backup.resolve(), directory, backup_passphrase, expected)
            elif recover:
                cert = LOCAL / "signing-cert.pem"
                key = LOCAL / "signing-key.pem"
                if not all(p.is_file() and not p.is_symlink() for p in (cert, key, LEGACY)):
                    raise SigningError("The original keychain, certificate and private key export are required for recovery.")
            else:
                cert = directory / "certificate.pem"
                key = directory / "private-key.pem"
                key_password = secrets.token_hex(32)
                run([OPENSSL, "req", "-new", "-newkey", "rsa:2048", "-x509",
                     "-days", "3650", "-subj", "/CN=Murmur Local Development/",
                     "-keyout", key, "-out", cert, "-addext", "extendedKeyUsage=codeSigning",
                     "-addext", "keyUsage=digitalSignature", "-passout", "stdin"],
                    data=(key_password + "\n").encode(), failure="Could not generate a signing identity.")

            fingerprint = certificate_fingerprint(cert)
            if recover:
                keychain_certificate(LEGACY, fingerprint)
            package = directory / "identity.p12"
            import_password = secrets.token_hex(32)
            # For a plaintext legacy PEM there is no input passphrase to read.
            input_password = "stdin" if key_password else "pass:"
            passwords = [key_password, import_password] if key_password else [import_password]
            run([OPENSSL, "pkcs12", "-export", "-out", package, "-inkey", key, "-in", cert,
                 "-passin", input_password, "-passout", "stdin"],
                data=("\n".join(passwords) + "\n").encode(),
                failure="Could not package the private key and its matching certificate.")
            password = secrets.token_hex(32)
            security("create-keychain", "-p", password, KEYCHAIN)
            created = True
            security("import", package, "-k", KEYCHAIN, "-P", import_password, "-T", CODESIGN, "-x")
            require_unexpired_certificate(keychain_certificate(KEYCHAIN, fingerprint))
            security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, KEYCHAIN)
            signing_probe(directory, fingerprint)

            security("add-generic-password", "-s", SERVICE, "-a", account, "-w", password, "-T", SECURITY, login)
            saved = True
            PIN.write_text(fingerprint + "\n")
            (STORE / ACCOUNT_FILE).write_text(account + "\n")
            security("lock-keychain", KEYCHAIN)
            complete = True
    finally:
        if not complete:
            if saved:
                security("delete-generic-password", "-s", SERVICE, "-a", account, login)
            if created:
                security("delete-keychain", KEYCHAIN)
            PIN.unlink(missing_ok=True)
            (STORE / ACCOUNT_FILE).unlink(missing_ok=True)
            STORE.rmdir()
    print(f"Keydown signing identity ready: {fingerprint}")


@contextmanager
def unlocked_identity():
    if STORE.is_symlink() or any(p.is_symlink() or not p.is_file() for p in (KEYCHAIN, PIN)):
        raise SigningError("Set up the managed signing identity with scripts/create_signing_identity.sh.")
    with (STORE / "build.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        fingerprint = PIN.read_text().strip()
        if not re.fullmatch(r"[A-F0-9]{40}", fingerprint):
            raise SigningError("The pinned signing certificate fingerprint is invalid.")
        require_unexpired_certificate(keychain_certificate(KEYCHAIN, fingerprint))
        login = login_keychain()
        require_unlocked_login(login)
        try:
            password = security("find-generic-password", "-s", SERVICE, "-a", saved_account(), "-w", login).decode().strip()
        except SigningError:
            raise SigningError("The saved Keydown credential is missing or inaccessible. See docs/SIGNING_RECOVERY.md.") from None
        if not re.fullmatch(r"[a-f0-9]{64}", password):
            raise SigningError("The saved Keydown signing credential is invalid.")
        try:
            security("unlock-keychain", "-p", password, KEYCHAIN)
        except SigningError:
            raise SigningError("The saved credential could not unlock the signing keychain. See docs/SIGNING_RECOVERY.md.") from None
        try:
            yield fingerprint
        finally:
            security("lock-keychain", KEYCHAIN)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    setup = actions.add_parser("setup")
    source = setup.add_mutually_exclusive_group()
    source.add_argument("--recover-legacy", action="store_true")
    source.add_argument("--restore-pkcs12", type=Path)
    setup.add_argument("--fingerprint", type=str.upper)
    actions.add_parser("check")
    sign = actions.add_parser("sign")
    sign.add_argument("app", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.action == "setup":
            if bool(args.restore_pkcs12) != bool(args.fingerprint):
                setup.error("--restore-pkcs12 and --fingerprint must be supplied together")
            configure(args.recover_legacy, args.restore_pkcs12, args.fingerprint)
        else:
            with unlocked_identity() as fingerprint:
                if args.action == "check":
                    with tempfile.TemporaryDirectory(prefix="keydown-signing-check-") as temp:
                        signing_probe(temp, fingerprint)
                    print(f"Keydown signing identity verified: {fingerprint}")
                else:
                    resources = args.app / "Contents/Resources"
                    for name in ("speech-decode", "text-complete"):
                        helper = resources / name
                        if helper.is_file():
                            codesign(helper, fingerprint)
                    run(["/usr/bin/python3", ROOT / "scripts/build_manifest.py", resources],
                        failure="Could not write the signed build manifest.")
                    codesign(args.app, fingerprint)
                    run([CODESIGN, "--verify", "--deep", "--strict", args.app],
                        failure="The signed app did not pass strict signature verification.")
    except (SigningError, OSError) as error:
        parser.exit(1, f"Keydown signing: {error}\n")


if __name__ == "__main__":
    main()
