#!/usr/bin/env python3
"""Build decoders from pinned trees and verify bytes staged for signing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
from patch_speech import patch_speech

ROOT = Path(__file__).resolve().parents[1]
REVISIONS = json.loads((ROOT / "docs/ENGINES.json").read_text())
SPEECH, EDITING = json.loads((ROOT / "docs/MODELS.json").read_text())
COMPACT = json.loads((ROOT / "docs/SPEECH_VARIANT.json").read_text())


def verified_copy(source, destination, digest, size=None):
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as original:
        info = os.fstat(original.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise SystemExit(f"Expected a regular staged input: {source.name}")
        limit = size if size is not None else 1024 * 1024
        if info.st_size > limit or (size is not None and info.st_size != size):
            raise SystemExit(f"Size mismatch: {source.name}")
        with destination.open("xb") as staged:
            remaining = limit
            for block in iter(lambda: original.read(min(4 * 1024 * 1024, remaining + 1)), b""):
                remaining -= len(block)
                if remaining < 0:
                    raise SystemExit(f"Size mismatch: {source.name}")
                staged.write(block)
    with destination.open("rb") as staged:
        fingerprint = hashlib.sha256()
        for block in iter(lambda: staged.read(4 * 1024 * 1024), b""):
            fingerprint.update(block)
    if fingerprint.hexdigest() != digest or (size is not None and destination.stat().st_size != size):
        raise SystemExit(f"Checksum or size mismatch: {source.name}")


def build(kind, work, *, prepare=False):
    name = "speech" if kind == "speech" else "text"
    vendor = ROOT / ".local/vendor" / f"{name}-engine"
    revision = REVISIONS[kind]
    git = ["/usr/bin/git", "--no-replace-objects", "-C", str(vendor)]
    if subprocess.check_output(git + ["rev-parse", "HEAD"], text=True).strip() != revision:
        raise SystemExit(f"The {name} engine checkout does not match its pinned revision.")
    if subprocess.check_output(git + ["status", "--porcelain", "--untracked-files=normal"]):
        raise SystemExit(f"The {name} engine checkout has local changes.")
    source = work / f"{name}-source"
    source.mkdir()
    with tempfile.TemporaryFile() as archive:
        subprocess.run(git + ["archive", "--format=tar", revision], stdout=archive, check=True)
        archive.seek(0)
        subprocess.run(["/usr/bin/tar", "-xf", "-", "-C", str(source)], stdin=archive, check=True)
    generator = os.environ.get("KEYDOWN_CMAKE") or shutil.which("cmake")
    if not generator or not Path(generator).is_absolute():
        raise SystemExit("Install trusted CMake or set KEYDOWN_CMAKE to its absolute path.")
    output = work / f"{name}-build"
    flags = ["-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF", "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"]
    if kind == "speech":
        patch_speech(source, ROOT)
        flags += ["-DWHISPER_BUILD_TESTS=OFF"]
        targets = ["whisper-cli"] + (["whisper-quantize"] if prepare else [])
    else:
        arg = source / "common/arg.cpp"
        code = arg.read_text()
        replacements = {
            "    common_params_apply_system_config(params, ctx_arg.ex);":
                "    // Keydown supplies all editing options explicitly.",
            "        common_models_handler handler = common_models_handler_init(params, ctx_arg.ex);\n"
            "        common_models_handler_apply(handler, params);":
                "        if (!params.offline) { throw std::invalid_argument(\"Keydown requires an offline model.\"); }",
        }
        for original, replacement in replacements.items():
            if code.count(original) != 1:
                raise SystemExit("Recheck the offline editing patch for the pinned engine.")
            code = code.replace(original, replacement)
        arg.write_text(code)
        flags += ["-DLLAMA_BUILD_TESTS=OFF", "-DLLAMA_BUILD_SERVER=OFF", "-DLLAMA_OPENSSL=OFF", "-DGGML_RPC=OFF"]
        targets = ["llama-completion"]
    subprocess.run([generator, "-S", str(source), "-B", str(output), *flags], check=True)
    subprocess.run([generator, "--build", str(output), "--target", *targets, "-j", "6"], check=True)
    return output / "bin", source / "LICENSE", targets


def stage(resources, work):
    models = ROOT / "models"
    compact = models / COMPACT["output"]
    speech = models / SPEECH["filename"]
    if (compact.is_file() or speech.is_file()) and (ROOT / ".local/vendor/speech-engine").is_dir():
        candidate, spec = (compact, COMPACT | {"sha256": COMPACT["output_sha256"]}) if compact.is_file() else (speech, SPEECH)
        verified_copy(candidate, resources / "speech-model.bin", spec["sha256"], spec["size"])
        binaries, license_file, _ = build("speech", work)
        shutil.copy2(binaries / "whisper-cli", resources / "speech-decode")
        (resources / "speech-protocol.json").write_text(json.dumps({"version": 1}))
        shutil.copyfile(license_file, resources / "SpeechEngine-LICENSE.txt")

    editing = models / EDITING["filename"]
    if editing.is_file() and (ROOT / ".local/vendor/text-engine").is_dir():
        verified_copy(editing, resources / "editing-model.gguf", EDITING["sha256"], EDITING["size"])
        verified_copy(ROOT / ".local/model-license.txt", resources / "EditingModel-LICENSE.txt", EDITING["license"]["sha256"])
        binaries, license_file, _ = build("editing", work)
        shutil.copy2(binaries / "llama-completion", resources / "text-complete")
        shutil.copyfile(license_file, resources / "TextEngine-LICENSE.txt")


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--resources", type=Path)
    group.add_argument("--prepare", choices=("speech", "editing"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="keydown-engines-") as temp:
        if args.resources:
            stage(args.resources.resolve(), Path(temp))
        else:
            binaries, _, targets = build(args.prepare, Path(temp), prepare=True)
            name = "speech" if args.prepare == "speech" else "text"
            output = ROOT / ".local" / f"{name}-build/bin"
            output.mkdir(parents=True, exist_ok=True)
            for target in targets:
                with tempfile.NamedTemporaryFile(dir=output, delete=False) as file:
                    staging = Path(file.name)
                try:
                    shutil.copy2(binaries / target, staging)
                    staging.replace(output / target)
                finally:
                    staging.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
