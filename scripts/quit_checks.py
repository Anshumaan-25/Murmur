#!/usr/bin/env python3
"""Exercise the installer quit helper against its own app and named pasteboards."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / ".build/Keydown Fixture.app"
EXE = APP / "Contents/MacOS/KeydownFixture"
BUNDLE_ID = "local.murmur.fixture"


def read(path):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            return path.read_text()
        except FileNotFoundError:
            time.sleep(0.025)
    raise RuntimeError(f"Timed out waiting for fixture {path.name}")


def main():
    if not EXE.is_file():
        raise SystemExit("Build the native fixture first with bash scripts/build_fixture.sh.")
    with tempfile.TemporaryDirectory(prefix="keydown-quit-check-") as folder:
        temporary = Path(folder).resolve()
        helper = temporary / "quit"
        subprocess.run(["xcrun", "swiftc", ROOT / "scripts/quit_installed_app.swift", "-o", helper], check=True)

        # A unique path prevents matching another open instance of the fixture.
        app = temporary / APP.name
        subprocess.run(["ditto", APP, app], check=True)
        executable = app / EXE.relative_to(APP)
        def quit_app(timeout=4, executable_path=executable, bundle=BUNDLE_ID):
            return subprocess.run([helper, bundle, str(timeout), executable_path],
                                  capture_output=True, text=True, timeout=timeout + 3)

        checks = {}
        for mode, expected in [("normal", "original fixture clipboard"),
                               ("new-owner", "new fixture owner"),
                               ("delayed", "original fixture clipboard"),
                               ("refuse", "original fixture clipboard"),
                               ("dirty", "original fixture clipboard")]:
            ready = temporary / mode
            report = ready.with_suffix(".result")
            allow = ready.with_suffix(".allow")
            subprocess.run(["open", "-g", "-n", app, "--args", "--quit-fixture", mode,
                            ready, "local.murmur.quit." + str(uuid.uuid4())], check=True)
            try:
                read(ready)
                child = int(read(ready.with_suffix(".child")))
                if mode == "refuse":
                    wrong_path = quit_app(executable_path=temporary / "unrelated")
                    wrong_bundle = quit_app(bundle="local.murmur.unrelated")
                    refused = quit_app(timeout=0.35)
                    checks["wrong_path_and_identifier_leave_fixture_running"] = (
                        wrong_path.returncode == 0 and wrong_bundle.returncode == 0 and not report.exists()
                    )
                    checks["refused_quit_aborts_update"] = refused.returncode != 0 and not report.exists()
                    allow.touch()
                if mode == "dirty":
                    cancelled = quit_app(timeout=1.25)
                    checks["dirty_quit_cancel_aborts_update"] = (
                        cancelled.returncode != 0 and not report.exists()
                        and read(ready.with_suffix(".decision")) == "cancel"
                    )
                    allow.touch()
                started = time.monotonic()
                result = quit_app()
                if result.returncode:
                    raise RuntimeError(result.stderr.strip())
                if mode == "delayed":
                    checks["installer_waits_for_delayed_quit"] = time.monotonic() - started >= 0.30
                checks[f"{mode}_clipboard_contents"] = read(report) == expected
                try:
                    os.kill(child, 0)
                except ProcessLookupError:
                    checks[f"{mode}_owned_decoder_drained"] = True
                else:
                    checks[f"{mode}_owned_decoder_drained"] = False
            finally:
                allow.touch()
                if not report.exists():
                    quit_app()
        print(json.dumps(checks, indent=2, sort_keys=True))
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
