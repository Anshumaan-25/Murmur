"""Identify the exact local sources and staged runtime without reading private files."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def source_identity(root):
    files = []
    for directory in ["Sources", "helpers", "scripts", "tests", "docs"]:
        files.extend(p for p in (root / directory).rglob("*")
                     if p.is_file() and p.suffix in {".swift", ".h", ".cpp", ".py", ".sh", ".json", ".md"})
    files.extend(root / name for name in ["Makefile", "Package.swift"] if (root / name).is_file())
    hashes = {}
    for file in sorted(files):
        if file.is_symlink():
            raise ValueError("Source identity refuses symlinks")
        hashes[str(file.relative_to(root))] = hashlib.sha256(file.read_bytes()).hexdigest()
    return hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()


def manifest(root, resources):
    revision = subprocess.run(["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True)
    assets = {}
    for name in ["speech-decode", "speech-model.bin", "speech-protocol.json", "text-complete", "editing-model.gguf", "cleanup-cases.json"]:
        path = resources / name
        if not path.is_file():
            continue
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        assets[name] = digest.hexdigest()
    return {"version": "0.2.4", "revision": revision.stdout.strip() if revision.returncode == 0 else "unknown",
            "source_sha256": source_identity(root), "rules": "cleanup-7", "speech_protocol": 1 if "speech-protocol.json" in assets else 0,
            "assets": assets}


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    resources = Path(sys.argv[1])
    (resources / "build-info.json").write_text(json.dumps(manifest(root, resources), sort_keys=True, indent=2) + "\n")
