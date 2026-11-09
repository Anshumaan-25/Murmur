"""Compare raw and formatted local dictation on an explicitly supplied audio corpus.

No downloads, microphone use or app preferences. Reports omit text unless requested.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import time
from benchmark import distance


def score(reference, result, protected=()):
    a = re.findall(r"\w+", reference.lower())
    b = re.findall(r"\w+", result.lower())
    missing = [term for term in protected if not re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", result)]
    return {"normalized_wer": distance(a, b) / max(1, len(a)),
            "character_edits": distance(reference, result), "missing_protected": missing}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--bench", type=Path, required=True)
    parser.add_argument("--decoder", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--private-protocol", action="store_true")
    parser.add_argument("--vocabulary-file", type=Path)
    parser.add_argument("--include-text", action="store_true")
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.repeats <= 5:
        parser.error("Use 1–5 repeats")
    samples = json.loads(args.corpus.read_text())
    if not isinstance(samples, list) or not 1 <= len(samples) <= 200:
        parser.error("Use a corpus of 1–200 utterances")
    rows = []
    for sample in samples:
        if max(len(sample["reference"]), len(sample.get("expected", ""))) > 10000:
            parser.error("Reference passages must be at most 10,000 characters")
        audio = (args.corpus.parent / sample["audio"]).resolve()
        for attempt in range(args.repeats):
            command = [str(args.bench.resolve()), "--file", str(audio), "--decoder", str(args.decoder.resolve()), "--model", str(args.model.resolve())]
            if args.private_protocol:
                command.append("--private-protocol")
            if args.vocabulary_file:
                command += ["--vocabulary-file", str(args.vocabulary_file.resolve())]
            began = time.monotonic()
            process = subprocess.run(command, capture_output=True, text=True, timeout=90)
            value = json.loads(process.stdout)
            row = {"id": sample["id"], "attempt": attempt, "wall_seconds": time.monotonic()-began,
                   "status": value.get("status", "invalid")}
            if value.get("status") == "ok":
                facts = sample.get("protected", [])
                row["recognition"] = score(sample["reference"], value["text"], facts)
                row["formatted"] = score(sample.get("expected", sample["reference"]), value["cleaned"], facts)
                # Report counts by default: even a missing fact can contain sensitive text.
                if not args.include_text:
                    for stage in ["recognition", "formatted"]:
                        row[stage]["missing_protected_count"] = len(row[stage].pop("missing_protected"))
                row["cleanup_changed_text"] = value["text"] != value["cleaned"]
                row["recognition_seconds"] = value["recognition_seconds"]
                row["audio_seconds"] = value["audio_seconds"]
                if args.include_text:
                    row.update(raw=value["text"], cleaned=value["cleaned"])
            rows.append(row)
    times = sorted(row["wall_seconds"] for row in rows if row["status"] == "ok")
    report = {"artifacts": {key: digest(getattr(args, key)) for key in ["bench", "decoder", "model"]},
              "utterances": len(samples), "runs": rows,
              "p50_seconds": statistics.median(times) if times else None,
              "p95_seconds": times[math.ceil(len(times)*0.95)-1] if times else None,
              "limits": "Local file decoding and deterministic cleanup. Each attempt starts a new helper; later attempts may benefit from OS caches. No microphone, recipient insertion, human correction count, energy, or aggregate helper memory is measured."}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive private output: never overwrite a prior evaluation accidentally.
    import os
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(report, output, indent=2)
    print(json.dumps({"utterances": len(samples), "runs": len(rows), "successful": len(times), "p50_seconds": report["p50_seconds"], "p95_seconds": report["p95_seconds"]}))


if __name__ == "__main__":
    main()
