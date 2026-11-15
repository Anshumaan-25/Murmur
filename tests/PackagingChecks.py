import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from replace_bundle import replace
import stage_engines


class PackagingChecks(unittest.TestCase):
    def test_build_identity_changes_with_source_not_private_data(self):
        from build_manifest import source_identity
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Sources").mkdir()
            code = root / "Sources/Fixture.swift"
            code.write_text("first")
            first = source_identity(root)
            (root / ".local").mkdir()
            (root / ".local/private.txt").write_text("fixture private data")
            self.assertEqual(first, source_identity(root))
            code.write_text("second")
            self.assertNotEqual(first, source_identity(root))

    def test_wrong_bytes_and_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "model.bin"
            source.write_bytes(b"wrong")
            expected = hashlib.sha256(b"right").hexdigest()
            with self.assertRaises(SystemExit):
                stage_engines.verified_copy(source, root / "staged", expected, 5)
            link = root / "link"
            link.symlink_to(source)
            with self.assertRaises(OSError):
                stage_engines.verified_copy(link, root / "staged-link", expected, 5)
            source.write_bytes(b"right")
            stage_engines.verified_copy(source, root / "staged-good", expected, 5)
            self.assertEqual((root / "staged-good").read_bytes(), b"right")

    def test_dirty_pinned_vendor_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            vendor = root / ".local/vendor/speech-engine"
            vendor.mkdir(parents=True)
            git = ["/usr/bin/git", "-C", str(vendor)]
            subprocess.run(git + ["init", "--quiet"], check=True)
            project = vendor / "CMakeLists.txt"
            project.write_text("# synthetic pinned source\n")
            subprocess.run(git + ["add", project.name], check=True)
            subprocess.run(git + ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                                  "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                                  "commit", "--quiet", "-m", "fixture"], check=True)
            revision = subprocess.check_output(git + ["rev-parse", "HEAD"], text=True).strip()
            project.write_text('message(FATAL_ERROR "this source must never be configured")\n')
            with patch.object(stage_engines, "ROOT", root), patch.dict(stage_engines.REVISIONS, speech=revision):
                with self.assertRaisesRegex(SystemExit, "local changes"):
                    stage_engines.build("speech", root)

    def test_signing_bootstrap_removes_exports_on_success_and_failure(self):
        import project_signing as signing

        for fail_import in (False, True):
            with self.subTest(fail_import=fail_import), tempfile.TemporaryDirectory() as directory:
                local = Path(directory) / ".local"
                store = local / "code-signing"
                keychain = store / "Keydown.keychain-db"
                pin = store / "certificate.sha1"
                temp_paths = []
                credentials = {}

                def security(command, *args):
                    if command == "create-keychain":
                        keychain.touch()
                    elif command == "import" and fail_import:
                        raise signing.SigningError("test import failure")
                    elif command == "delete-keychain":
                        keychain.unlink()
                    elif command == "add-generic-password":
                        credentials["password"] = args[5]
                    return b""

                def run(args, **kwargs):
                    if "pkcs12" in args:
                        temp_paths.append(args[args.index("-out") + 1].parent)
                    return b""

                with patch.multiple(signing, LOCAL=local, LEGACY=local / "signing.keychain-db",
                                    STORE=store, KEYCHAIN=keychain, PIN=pin), \
                     patch.object(signing, "security", side_effect=security), \
                     patch.object(signing, "run", side_effect=run), \
                     patch.object(signing, "login_keychain", return_value=Path("login.keychain-db")), \
                     patch.object(signing, "require_unlocked_login"), \
                     patch.object(signing, "certificate_fingerprint", return_value="A" * 40), \
                     patch.object(signing, "keychain_certificate"), \
                     patch.object(signing, "signing_probe"):
                    if fail_import:
                        with self.assertRaisesRegex(signing.SigningError, "test import failure"):
                            signing.configure(False)
                        self.assertFalse(store.exists())
                        self.assertFalse(credentials)
                    else:
                        signing.configure(False)
                        self.assertEqual(pin.read_text().strip(), "A" * 40)
                        self.assertRegex(credentials["password"], r"^[a-f0-9]{64}$")
                        self.assertEqual(sorted(p.name for p in store.iterdir()),
                                         ["Keydown.keychain-db", "certificate.sha1", "credential-account"])
                self.assertTrue(temp_paths)
                self.assertTrue(all(not path.exists() for path in temp_paths))

    def test_signed_bundle_replacement_and_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installed = root / "Live.app"
            staged = root / "Staged.app"
            for bundle in [installed, staged]:
                executable = bundle / "Contents/MacOS/Fixture"
                executable.parent.mkdir(parents=True)
                shutil.copyfile("/usr/bin/true", executable)
                executable.chmod(0o700)
                (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleExecutable": "Fixture", "CFBundleIdentifier": "local.murmur.packaging-fixture",
                    "CFBundlePackageType": "APPL",
                }))
                if bundle == installed:
                    resource = bundle / "Contents/Resources/obsolete"
                    resource.parent.mkdir()
                    resource.write_bytes(b"fixture")
                subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", bundle],
                               check=True, capture_output=True)
            verify = ["/usr/bin/codesign", "--verify", "--deep", "--strict", installed]
            replace(staged, installed)
            self.assertFalse((installed / "Contents/Resources/obsolete").exists())
            subprocess.run(verify, check=True)
            replace(staged, installed)
            self.assertTrue((installed / "Contents/Resources/obsolete").is_file())
            subprocess.run(verify, check=True)


if __name__ == "__main__":
    unittest.main()
