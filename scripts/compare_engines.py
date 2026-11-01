#!/usr/bin/env python3
"""Bounded, reproducible comparison of installed local speech paths."""
import json
import pathlib
import statistics
import subprocess
import time
import wave
from benchmark import CLIPS, tokens, distance

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    subprocess.run(["swift", "build", "-c", "release", "--product", "murmur-bench"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    binary = pathlib.Path(subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True).strip()) / "murmur-bench"
    paths = [
        ("bundled_gpu", ["--decoder", str(ROOT / ".local/speech-build/bin/whisper-cli"), "--model", str(ROOT / "models/ggml-small.en.bin")]),
        ("bundled_cpu", ["--decoder", str(ROOT / ".local/speech-build/bin/whisper-cli"), "--model", str(ROOT / "models/ggml-small.en.bin"), "--cpu"]),
        ("system_analyzer", ["--engine", "analyzer"]),
        ("system_dictation", ["--engine", "legacy"]),
    ]
    quantized = ROOT / "models/ggml-small.en-q5_1.bin"
    if quantized.exists():
        paths.insert(2, ("bundled_q5", ["--decoder", str(ROOT / ".local/speech-build/bin/whisper-cli"), "--model", str(quantized)]))
    records = []; budget_end = time.monotonic() + 1200
    for name, reference in CLIPS:
        file = ROOT / "tests/audio" / (name + ".wav"); file.parent.mkdir(exist_ok=True)
        subprocess.run(["say", "-v", "Samantha", "--data-format=LEI16@16000", "-o", str(file), reference], check=True)
        if name == "ten-seconds":
            with wave.open(str(file), "rb") as audio:
                params = audio.getparams(); data = audio.readframes(audio.getnframes())
            if len(data) < 320000:
                with wave.open(str(file), "wb") as audio:
                    audio.setparams(params); audio.writeframes(data + bytes(320000 - len(data)))
        for path, options in paths:
            for attempt in range(2):
                if time.monotonic() > budget_end:
                    raise SystemExit("Comparison time budget exhausted.")
                start = time.monotonic()
                try:
                    result = subprocess.run([str(binary), "--file", str(file), *options], cwd=ROOT, text=True, capture_output=True, timeout=90)
                    data = json.loads(result.stdout)
                except (subprocess.TimeoutExpired, json.JSONDecodeError):
                    data = {"status": "unavailable", "reason": "The candidate timed out or did not return structured results."}
                data.update(candidate=path, clip=name, attempt=attempt, wall_seconds=time.monotonic() - start)
                if data.get("status") == "ok":
                    data["normalized_wer"] = distance(tokens(reference), tokens(data["text"])) / len(tokens(reference))
                records.append(data)
                if data.get("status") != "ok":
                    break
    summary = {}
    for name, _ in paths:
        samples = [r for r in records if r["candidate"] == name]
        successful = [r for r in samples if r.get("status") == "ok"]
        summary[name] = {"successful_samples": len(successful), "unavailable_samples": len(samples) - len(successful)}
        if successful:
            summary[name].update(p50_seconds=statistics.median(r["wall_seconds"] for r in successful), mean_wer=statistics.mean(r["normalized_wer"] for r in successful))
        else:
            summary[name]["reason"] = samples[0]["reason"]
    available = {name: row for name, row in summary.items() if row["successful_samples"] == len(CLIPS) * 2}
    best_error = min(row["mean_wer"] for row in available.values()) if available else 0
    eligible = {name: row for name, row in available.items() if row["mean_wer"] <= best_error + 0.005}
    selected = min(eligible, key=lambda name: eligible[name]["p50_seconds"]) if eligible else "none"
    output = {"summary": summary, "samples": records, "selection": selected, "limits": "Synthetic fixed clips; process startup included. Microphone and destination insertion are outside this comparison. Additional model frameworks are not installed, so they are not reported as measured."}
    (ROOT / "docs/SPEECH_COMPARISON.json").write_text(json.dumps(output, indent=2))
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
