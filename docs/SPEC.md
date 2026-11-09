# Murmur behavioral specification

This document is the sole bridge from the reference analysis to the independent implementation. Labels describe evidence about the reference, not promises about the new application. No reference implementation source, proprietary assets, service addresses, credentials, or prompts belong in this repository.

## Lifecycle and audio

OBSERVED (E02–E07): microphone acquisition requests a single channel at sixteen thousand samples per second. Work is grouped into forty-millisecond sample batches. Compressed audio is another packaged option. Capture and the interface run in different execution contexts.

OBSERVED (E07, E10–E11): a recording carries an identity; queued audio reaches a remote recognition stage; finishing commits the utterance. Intermediate updates and a completed response are separate. Late responses can be rejected.

INFERRED (E07, E10): a useful abstract lifecycle is idle, listening, processing, inserting, then idle. Independent design: cancellation invalidates the recording identity immediately; errors are recoverable; a newer identity supersedes all older work. No insertion occurs twice for one identity.

## Recognition and cleanup

OBSERVED (E08, E12–E14): recognition, alignment, and optional language cleanup are remote stages. Alternative remote request routes exist. Their protocols are not part of this specification.

OBSERVED (E11): recognized wording, edited wording, and destination content are independently represented.

UNKNOWN: remote models, training material, instruction templates, and quality guarantees. Independent design: an offline speech provider returns recognition text; a separate cleanup provider receives text and local context. Batch inference on release is acceptable initially. Interfaces accept sample batches and may emit intermediate text later.

## Context

OBSERVED (E09, E17): app identity, selected and neighboring text, vocabulary, and optional screen-derived words can accompany recognition. INFERRED: these inputs improve spelling and adapt presentation to the destination. Presence of a serialized field does not prove collection during a session.

Independent design: collect destination identity first. Additional selected and neighboring text requires Accessibility access and is never read from a protected control. No screen capture or optical recognition is required initially. No context leaves this computer.

## Insertion and permissions

OBSERVED (E15–E16): insertion dispatches plain and optionally rich text to a native component. OBSERVED (E19–E20): native capabilities include clipboard access, accessibility inspection, keyboard events, and clipboard recovery diagnostics.

INFERRED (E15–E20): ordinary insertion uses an offered clipboard item and a paste gesture. Exact app exceptions are UNKNOWN. Current independent design: remember every available pasteboard type on every item; restore after a configurable interval unless another clipboard owner replaced our content. Refuse protected fields. Remember app and focused control; when they change, make the result available for explicit Copy/Review without changing the clipboard. A dispatched paste is unconfirmed until a recipient is observed consuming it. Selected-text delivery revalidates the exact selection and retains target-owned undo.

OBSERVED (E19): native permission checks and event monitoring exist. Independent design: provide microphone, Accessibility, and optional Input Monitoring onboarding. A registered toggle shortcut works without Input Monitoring. Model installation permission is separate from microphone access.

## Modes and controls

OBSERVED (bounded supplementary search B01): packaged code contains press-and-hold handling with separate start/stop callbacks and an active recording identity. UNKNOWN: gesture thresholds, all key combinations, exact double-tap rules, and conflict handling.

Independent design: a registered toggle shortcut is the fallback. Holding a configured key records until release when monitoring permission is present. Escape cancels. Hands-free capture ends on sustained silence or a maximum duration. A dedicated shortcut attempts delivery of the latest result after destination checks. Spoken Return is not an action; literal “press enter” remains text. Starting another recording while processing requires explicit cancellation first.

OBSERVED (bounded supplementary search B01): command-related status and mode branches exist. UNKNOWN: their complete behavior and remote instructions. Independent design: capture selected text at the start, recognize a spoken editing request, rewrite locally, and replace only the unchanged original selection. Unsupported instructions show an explanation rather than inventing an edit. Replacement uses a normal paste operation so the destination owns undo.

## Floating indicator

UNKNOWN: full reference window construction, geometry, docking, and animation details. Independent design: a compact nonactivating panel appears across Spaces and alongside fullscreen apps, renders microphone level, and indicates capture, processing, completion, cancellation, or failure. It must not take keyboard focus. Its location is saved locally; dragging docks it near the closest screen edge.

## Local information and settings

OBSERVED (bounded supplementary search B01): vocabulary and expansion features appear in packaged code. A local retention choice includes preserving history, expiring it after a day, and disabling storage. UNKNOWN: complete schemas, ordering, search strategy, and all editor behavior.

Independent design: SQLite holds utterances (identity, time, destination, duration, three text stages, outcome, latency), vocabulary terms, spoken expansions, and app-specific style rules. Settings cover microphone, language, shortcuts, silence timeout, duration limit, clipboard recovery delay, model path, optional cleanup, audio persistence, retention, and startup registration. Logs contain event categories and timings only. Audio persistence is off initially. A local hub supports search, copy, deletion, export, aggregate statistics, and editing these settings.

## Implementation substitutions

| Stage | Reference location | Local candidates |
|---|---|---|
| Sound acquisition | Desktop client | Native audio engine and conversion |
| Speech decoding | Remote infrastructure | System speech analysis; packaged local decoder |
| Wording cleanup | Remote infrastructure | Deterministic editing rules; optional local instruction model |
| Editing selected text | Partially unknown; remote assistance inferred | Local deterministic commands; optional system language model |
| Destination integration | Native desktop component | Accessibility inspection and clipboard paste |
| Personalization storage | Desktop plus services; incomplete evidence | SQLite and local preferences |

The analytical investigation is closed. Implementation choices and unresolved points are recorded in DECISIONS.md without reopening its inputs.
