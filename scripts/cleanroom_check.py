#!/usr/bin/env python3
"""Compare project-owned text against the external analysis input without revealing it."""
import pathlib
import re
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "inspection"
SKIP = {".git", ".build", ".local", "models", "artifacts", ".build-cache"}

def normalized(value):
    return " ".join(value.split())

def project_files():
    for path in ROOT.rglob("*"):
        if path.is_file() and not any(part in SKIP for part in path.relative_to(ROOT).parts):
            yield path

def main():
    if not SOURCE.is_dir():
        print("External analysis directory unavailable; verification cannot run.", file=sys.stderr)
        return 2
    corpus = []
    hosts = set()
    for path in SOURCE.rglob("*"):
        if not path.is_file() or path.suffix not in {".txt", ".md", ".js", ".json", ".proto", ".mjs", ".html"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            continue
        corpus.append(normalized(text))
        for candidate in re.findall(r'https?://[A-Za-z0-9][A-Za-z0-9.\-]*(?::[0-9]+)?(?:/[^\s\x22\x27<>\\]*)?', text):
            host = urlsplit(candidate).hostname
            if host and "." in host and len(host) > 4:
                hosts.add(host.lower())
    merged = "\n".join(corpus)
    failures = set()
    for path in project_files():
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            compact = normalized(line)
            if len(compact) >= 40 and compact in merged:
                failures.add((str(path.relative_to(ROOT)), number))
            if any(re.search(r'(?<![a-z0-9.-])' + re.escape(host) + r'(?![a-z0-9.-])', line.lower()) for host in hosts):
                failures.add((str(path.relative_to(ROOT)), number))
    for name, number in sorted(failures):
        print(f"{name}:{number}")
    if not failures:
        print("Clean-room check passed.")
    return int(bool(failures))

if __name__ == "__main__":
    raise SystemExit(main())
