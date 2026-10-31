#!/usr/bin/env python3
"""Explicit one-time model retrieval with pinned size and digest checks."""
import argparse
import hashlib
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--confirm", action="store_true", help="Authorize the pinned model downloads")
    parser.add_argument("--speech-only", action="store_true")
    args = parser.parse_args()
    if not args.confirm:
        parser.error("Downloads require --confirm; review docs/MODELS.json first.")
    items = json.loads((ROOT / "docs" / "MODELS.json").read_text())
    folder = ROOT / "models"; folder.mkdir(exist_ok=True)
    for item in items:
        if args.speech_only and item["purpose"] != "speech":
            continue
        target = folder / item["filename"]
        def digest(path):
            hasher = hashlib.sha256()
            with path.open("rb") as source:
                for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
                    hasher.update(block)
            return hasher.hexdigest()
        if "license" in item:
            notice = item["license"]
            address = "https://huggingface.co/" + notice["repository"] + "/resolve/" + notice["revision"] + "/" + notice["filename"]
            license_path = ROOT / ".local" / "model-license.txt"
            license_path.parent.mkdir(exist_ok=True)
            if not license_path.exists() or digest(license_path) != notice["sha256"]:
                content = urllib.request.urlopen(address, timeout=30).read()
                if hashlib.sha256(content).hexdigest() != notice["sha256"]:
                    raise SystemExit("License verification failed.")
                license_path.write_bytes(content)
        if target.exists() and target.stat().st_size == item["size"] and digest(target) == item["sha256"]:
            print(item["purpose"] + ": verified existing model")
            continue
        address = "https://huggingface.co/" + item["repository"] + "/resolve/" + item["revision"] + "/" + item["filename"]
        partial = target.with_suffix(target.suffix + ".partial")
        with urllib.request.urlopen(address, timeout=60) as response, partial.open("wb") as output:
            while block := response.read(4 * 1024 * 1024):
                output.write(block)
        if partial.stat().st_size != item["size"] or digest(partial) != item["sha256"]:
            raise SystemExit("Model verification failed; the partial file was not activated.")
        partial.replace(target)
        print(item["purpose"] + ": downloaded and verified")

if __name__ == "__main__":
    main()
