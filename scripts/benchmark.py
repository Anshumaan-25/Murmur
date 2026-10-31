#!/usr/bin/env python3
"""Generate public synthetic speech and measure actual local decoding."""
import json
import pathlib
import re
import statistics
import subprocess
import time
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIPS = [
    ("meeting", "Please send the revised meeting notes to the design team before four tomorrow afternoon."),
    ("numbers", "The delivery contains twenty three boxes and costs one hundred dollars. We should meet on Tuesday at nine."),
    ("correction", "I think we should meet at three, actually make that four. Please bring the quarterly report."),
    ("ten-seconds", "Please send the revised meeting notes to our design team before four tomorrow afternoon and include the updated budget and schedule."),
]

def tokens(text):
    replacements = {"twenty three": "23", "one hundred": "100", "three": "3", "four": "4", "nine": "9"}
    text = text.lower()
    for source, target in replacements.items():
        text = re.sub(r"\b" + source + r"\b", target, text)
    return re.findall(r"\w+", text)

def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        row = [i]
        for j, right in enumerate(b, 1):
            row.append(min(previous[j] + 1, row[-1] + 1, previous[j - 1] + (left != right)))
        previous = row
    return previous[-1]

def main():
    subprocess.run(["swift", "build", "-c", "release", "--product", "murmur-bench"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    bin_path = subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True).strip()
    records = []
    for name, reference in CLIPS:
        file = ROOT / "tests" / "audio" / (name + ".wav")
        subprocess.run(["say", "-v", "Samantha", "--data-format=LEI16@16000", "-o", str(file), reference], check=True)
        if name == "ten-seconds":
            with wave.open(str(file), "rb") as audio:
                parameters = audio.getparams(); samples = audio.readframes(audio.getnframes())
            if len(samples) < 320000:
                with wave.open(str(file), "wb") as audio:
                    audio.setparams(parameters); audio.writeframes(samples + bytes(320000 - len(samples)))
        for attempt in range(3):
            command = [str(pathlib.Path(bin_path) / "murmur-bench"), "--file", str(file), "--decoder", str(ROOT / ".local/speech-build/bin/whisper-cli"), "--model", str(ROOT / "models/ggml-small.en.bin")]
            start = time.monotonic(); completed = subprocess.run(command, check=True, text=True, capture_output=True, timeout=90)
            record = json.loads(completed.stdout); record["wall_seconds"] = time.monotonic() - start
            record["clip"] = name; record["attempt"] = attempt
            record["word_error_rate"] = distance(tokens(reference), tokens(record["text"])) / len(tokens(reference))
            records.append(record)
    result = {"synthetic_voice": "Samantha", "records": records, "p50_wall_seconds": statistics.median(x["wall_seconds"] for x in records), "mean_wer": statistics.mean(x["word_error_rate"] for x in records), "note": "Decoder process startup included. Includes a ten-second PCM input. Microphone and insertion are not measured here."}
    long_runs = [record for record in records if record["clip"] == "ten-seconds"]
    result["ten_second_decoder_p50"] = statistics.median(record["wall_seconds"] for record in long_runs)
    (ROOT / "docs" / "BENCHMARK.json").write_text(json.dumps(result, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != "records"}, indent=2))

if __name__ == "__main__":
    main()
