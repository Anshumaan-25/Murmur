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
        root = Path(__file__).resolve().parents[1]
        for fail_import in (False, True):
            with self.subTest(fail_import=fail_import), tempfile.TemporaryDirectory() as directory:
                sandbox = Path(directory)
                scripts = sandbox / "scripts"
                scripts.mkdir()
                shutil.copyfile(root / "scripts/create_signing_identity.sh", scripts / "create_signing_identity.sh")
                temp = sandbox / "temp"
                temp.mkdir()
                openssl = scripts / "openssl"
                openssl.write_text("""#!/bin/bash
if [ "$1" = rand ]; then printf '%s\\n' fixture; exit; fi
while [ "$#" -gt 1 ]; do
    case "$1" in -out|-keyout) printf '%s\\n' synthetic > "$2"; shift;; esac
    shift
done
""")
                security = scripts / "security"
                security.write_text("""#!/bin/bash
case "$1" in
    create-keychain) touch "$4";;
    import)
        test "$9" = -x || exit 2
        if [ "$KEYDOWN_FIXTURE_FAIL_IMPORT" = 1 ]; then exit 3; fi;;
    delete-keychain) unlink "$2";;
esac
""")
                openssl.chmod(0o700)
                security.chmod(0o700)
                env = {**os.environ, "PATH": f"{scripts}:/usr/bin:/bin", "TMPDIR": str(temp),
                       "KEYDOWN_SIGNING_PASSWORD": "fixture-only", "KEYDOWN_FIXTURE_FAIL_IMPORT": str(int(fail_import))}
                result = subprocess.run(["/bin/bash", scripts / "create_signing_identity.sh"],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 3 if fail_import else 0, result.stderr)
                self.assertFalse(list(temp.iterdir()))
                expected = [] if fail_import else ["signing.keychain-db"]
                self.assertEqual(sorted(path.name for path in (sandbox / ".local").iterdir()), expected)

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
