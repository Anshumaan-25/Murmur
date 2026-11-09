# Dictation polish and qualification

This implementation builds on the security fixes in the working tree. The product review and local test artifacts are kept separately in ignored `.local` paths. A passing automated suite does not qualify the installed application, live microphone, physical sleep/wake, or an external recipient.

## Behavior

- Recording starts in `starting`; the first converted audio buffer advances the same session to `listening`. The indicator and menu bar both expose capture state. No-buffer and stale-buffer timeouts cancel capture. Quiet input is preserved for decoding; the meter distinguishes quiet, clipped and silent input. This is not a speech/noise classifier.
- The indicator sets floating behavior before its final window level. Each show restores opacity, level and valid geometry. A presentation generation prevents an old dismissal from hiding a newer session. Docking is normalized to the selected screen; legacy absolute positions are clamped. Wake leaves capture stopped and the indicator hidden until another explicit start. Settings preview/reset requires no microphone.
- A single active job owns capture, decode and delivery. Pressing again while processing gives a busy message; Escape explicitly cancels. Existing session identity, focus continuity, protected-field and clipboard ownership checks remain in force.
- Prose cleanup protects quoted literals, URLs, email, configured spellings and mixed-case names through the formatting pipeline. It preserves literal “scratch that”, “never mind”, “well” and “you know”; parses a narrow explicit time correction including dotted or attached meridiem; handles supported numeric corrections across a sentence boundary; and avoids converting the pronoun in “the second one”. These are bounded rules, not natural-language understanding.
- Exact text skips ordinary formatting, except a fully recognized whole-utterance `spell …` command. Prose mode overrides app-category inference; Follow app preference preserves the previous code/terminal behavior.
- Recognition hints use bounded UTF-8 in a versioned private stream to the bundled decoder. A pinned-source build patch adds the parser and bounded audio read. Invalid versions, UTF-8, lengths and oversize input fail. Custom executables do not receive hints; they still require explicit byte approval. English regions share one English model.
- Recovery offers Copy and Review. The review window shows recognition and an editable result, with the changed passage highlighted in both. A highlight can include unchanged words between edits; it is not a semantic diff or proof that facts are safe. Free-form selected-text suggestions use the same before/after review and remain manually copied.
- Practice uses an app-owned window. Keep it focused or use its button; its session result bypasses history, retained audio and cross-app insertion. Closing it cancels an active practice session and clears its text. Explicit Copy and saving a hint are still allowed.
- Version, source identity, rules revision and hashes of staged models/helpers are embedded. Diagnostic exports include bounded session metadata, not text or audio. They identify draw dispatch, not actual compositor visibility.

## Tests and evaluation

`make test` runs Swift behavior/process/storage/cleanup checks and Python packaging, actual C++ parser, and scoring checks. New behavior was introduced with failing regression checks before implementation. Native checks live only in a separately identified fixture build and exercise real AppKit controls and named clipboards. `KEYDOWN_ADHOC=1 bash scripts/build_app.sh` builds an isolated ad hoc candidate without using the development signing keychain; it does not install it.

`scripts/evaluate_corpus.py` accepts an explicit JSON array of objects with `id`, `audio`, `reference`, optional `expected` formatted text, and optional `protected` exact strings. Audio paths are relative to the manifest. Use neutral synthetic IDs. It launches the chosen benchmark/decoder with the chosen model, compares recognition and formatting separately, and writes an exclusive mode-0600 report. Text and missing-fact strings are omitted by default; `--include-text` opts in. Files are never downloaded or recorded by this tool. Vocabulary is an optional local UTF-8 file, one term per line.

Example, using explicitly supplied absolute paths:

```sh
python3 scripts/evaluate_corpus.py /path/to/corpus.json \
  --bench /path/to/murmur-bench --decoder /path/to/speech-decode \
  --model /path/to/speech-model.bin --private-protocol \
  --vocabulary-file /path/to/vocabulary.txt --repeats 2 \
  --output /path/to/new-report.json
```

The metrics separate normalized word error from exact protected facts. They include per-run timing and executable/model hashes. They do not measure human corrections, microphone onset, actual paste consumption, energy or total helper memory. Repeated processes can benefit from OS caches. Five synthetic Samantha clips are only a smoke set, not sufficient to choose a model or establish Indian English/name accuracy. The default compact model is unchanged pending a held-out human corpus and vocabulary off/on controls.

## Remaining qualification

Use the expanded manual matrix in `MANUAL_TESTS.md` with disposable text. Prioritize the reported built-in display/windowed Codex scenario after physical sleep. A synthetic lifecycle notification cannot reproduce WindowServer or hardware behavior. Native fullscreen, multiple displays, VoiceOver, Reduce Motion, mic onset/tail/device loss, real noise, external paste/undo and a stable-identity signed upgrade remain separate gates.

Adaptive voice activity, live partial transcription, multiple concurrent jobs, automatic application of model suggestions and always-listening capture are not introduced. A corpus that includes the user's own accent and intended names is needed before tuning recognition. Do not use silent fuzzy replacements to conceal decoder mistakes.

## Adversarial follow-up (cleanup-5)

Automatic correction no longer uses arbitrary words as operands; numeric operands use boundaries that exclude partial IDs. Standalone ambiguous “one” stays prose except explicit quantity contexts. Exact spelling accepts a terminal ASR period and a narrow compact identifier/version operand after “spell”; a spoken `dot` still produces a literal period. The bundled provider rejects an entire `[BLANK_AUDIO]` sentinel as empty, preserving custom-provider and embedded literal text.

Optional edit checks now protect cannot/can, additional number words and rupees. Unconfigured lowercase names and arbitrary semantic equivalence still require manual review; suggestions remain copy-only.

Hands-free uses a separate energy baseline measured during the first 300 ms, requiring activity above three times that baseline and an RMS minimum of .001. Quiet audio is still retained unchanged for recognition. Stationary noise no longer continually refreshes the speech clock in the synthetic regression. This fallback is not a validated voice classifier: speech during calibration, changing noise and extremely quiet speech may require explicit stopping; the hard cap remains. Real microphone qualification is required before calling this issue fully resolved.
