#!/usr/bin/env python3
"""Compare project-owned text against the external analysis input without revealing it."""
import pathlib
import re
import subprocess
import hashlib
import json
import shutil
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
    cache = ROOT / ".local" / "cleanroom"
    cache.mkdir(parents=True, exist_ok=True)
    inputs = [p for p in SOURCE.rglob("*") if p.is_file() and p.suffix in {".txt", ".md", ".js", ".json", ".proto", ".mjs", ".html"}]
    identity = hashlib.sha256(("bare-hosts-v2" + json.dumps([(str(p.relative_to(SOURCE)), p.stat().st_size, p.stat().st_mtime_ns) for p in sorted(inputs)])).encode()).hexdigest()
    combined_path = cache / (identity + ".txt")
    hosts_path = cache / (identity + ".json")
    if not combined_path.exists() or not hosts_path.exists():
        hosts = set()
        with combined_path.open("w") as combined:
            for path in inputs:
                try:
                    text = path.read_text(encoding="utf-8")
                except (UnicodeError, OSError):
                    continue
                combined.write(normalized(text) + "\n")
                hosts.update(h.lower() for h in re.findall(r"(?<![A-Za-z0-9.-])(?:[A-Za-z0-9][A-Za-z0-9-]*\.)+(?:com|org|net|io|ai|co|app|dev|cloud|edu|gov)(?![A-Za-z0-9.-])", text))
                for candidate in re.findall(r'(?:https?|wss?)://[A-Za-z0-9][A-Za-z0-9.\-]*(?::[0-9]+)?', text):
                    host = urlsplit(candidate).hostname
                    if host and "." in host and len(host) > 4:
                        hosts.add(host.lower())
        hosts_path.write_text(json.dumps(sorted(hosts)))
    hosts = json.loads(hosts_path.read_text())
    host_pattern = re.compile(r"(?<![a-z0-9.-])(?:" + "|".join(re.escape(h) for h in hosts) + r")(?![a-z0-9.-])", re.IGNORECASE) if hosts else None
    failures = set()
    candidates = {}
    for path in project_files():
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            location = (str(path.relative_to(ROOT)), number)
            compact = normalized(line)
            if len(compact) >= 40:
                candidates.setdefault(compact, []).append(location)
            if host_pattern and host_pattern.search(line):
                failures.add(location)
    pattern_path = cache / "project-lines.txt"
    pattern_path.write_text("\n".join(candidates) + "\n")
    if shutil.which("rg"):
        result = subprocess.run(["rg", "--fixed-strings", "--only-matching", "--no-filename", "--no-line-number", "--no-heading", "--color", "never", "--file", str(pattern_path), str(combined_path)], text=True, capture_output=True)
        if result.returncode not in (0, 1):
            print("Comparison could not complete.", file=sys.stderr)
            return 2
        for hit in set(result.stdout.splitlines()):
            failures.update(candidates.get(hit, []))
    else:
        merged = combined_path.read_text()
        for line, locations in candidates.items():
            if line in merged:
                failures.update(locations)
    for name, number in sorted(failures):
        print(f"{name}:{number}")
    if not failures:
        print("Clean-room check passed.")
    return int(bool(failures))

if __name__ == "__main__":
    raise SystemExit(main())
