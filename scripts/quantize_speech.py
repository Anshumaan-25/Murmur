#!/usr/bin/env python3
"""Derive and verify the selected compact model from an already downloaded model."""
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()

def main():
    spec = json.loads((ROOT / "docs/SPEECH_VARIANT.json").read_text())
    source = ROOT / "models" / spec["source"]; destination = ROOT / "models" / spec["output"]
    if not source.exists() or digest(source) != spec["source_sha256"]:
        raise SystemExit("The original speech model must be downloaded and verified first.")
    if destination.exists() and digest(destination) == spec["output_sha256"]:
        print("Compact speech model already verified.")
        return
    staging = destination.with_suffix(".partial.bin")
    subprocess.run([str(ROOT / ".local/speech-build/bin/whisper-quantize"), str(source), str(staging), spec["quantization"]], check=True)
    if staging.stat().st_size != spec["size"] or digest(staging) != spec["output_sha256"]:
        raise SystemExit("Derived model verification failed; the original model remains available.")
    staging.replace(destination)
    print("Compact speech model derived and verified.")

if __name__ == "__main__":
    main()
