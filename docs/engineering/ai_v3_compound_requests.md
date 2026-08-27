# AI V3 Generalized Compound Requests

Owner: AI Engineering  
Status: In review  
Last reviewed: 2026-08-28  
PDF: [ai_v3_compound_requests.pdf](ai_v3_compound_requests.pdf)  
Tickets: [PRO-16](https://linear.app/mixroom/issue/PRO-16/ai-generalized-compound-requests)
(parent), [PRO-18](https://linear.app/mixroom/issue/PRO-18/generalized-compound-requests-basic-architecture)
(architecture), [PRO-19](https://linear.app/mixroom/issue/PRO-19/generalized-compound-requests-support-more-cases)
(coverage)

Working record of the compound-request work: what was wrong, what
changed, how Mixroom behaves now, and which live and unit tests were
run. Nightcore, chipmunk, orbit, and garage are **eval prompts**, not
product modes.

Architecture stays
[ADR 0002](adr/0002-ai-v3-architecture.md): one V3 planner,
Flutter prepares and executes. ChatGPT’s 13-step remix essay (import,
invented drums, master, export) is not acceptance.

## Problem

Vague production goals (“make this a nightcore remix”, “orbit in
headphones”, “make this a garage remix”) collapsed to the nearest
single command, usually `clip.align_tempo_to_project`. Named singles
(“make this louder”, “pitch the vocal +3”) were already reliable. Style
goals were not.

An earlier prototype injected per-genre recipes (regex + hardcoded
semitones / BPM ratios). That overfit named styles and was rejected.
The replacement is a **request-independent musical-dimension compiler**:
the same instructions on every planner call. Flutter never matches genre
names.

## What changed

| Area | Before | After |
| --- | --- | --- |
| Style / remix / listening-format goals | Often one nearby edit (tempo-align) | One plan with every Mixroom-legal implied step: tempo, pitch, mix, pan automation; arrangement only when the user asked |
| Planner prompt | No always-on compiler; brief genre injection was tried and dropped | `aiV3MusicalDimensionCompilerInstructions` on every V3 request, including adaptive first-shot and continuation. The app sends that text as `instructions`; `/v1/llm/v3/responses` forwards it and only pins model / reasoning / `store`. |
| Align-only collapse | First plan could ship as tempo-align only | Retry when the plan's `goal_kind` is `production_goal` **and** every command is `clip.align_tempo_to_project`. Flutter does not regex the user string |
| Pan / gain automation | `mix:pan` / `mix:gain` often missing from context | Every audio row always exposes `volume`, `mix:gain`, `mix:pan` |
| Static pan vs sweep | Orbit could also emit mix-widen / static pan | If the plan writes `automation.set_points` on `mix:pan`, pan intents are stripped from `mix.apply_goal` |
| Pitch-only metaphors (“chipmunk”, “squeaky”) | Could pull a full nightcore stack, including after a remix turn in the same chat | Named pitch edit only. Classify from ORIGINAL_REQUEST_VERBATIM; do not repeat the previous plan's tempo/mix. Tape-speed folklore does not add tempo unless this request names speed or a remix/version goal. Defaults stay a few semitones, not an octave, unless the user names an amount |
| Implied vs explicit arrangement | Style goals could place library drums if assets existed; explicit “add drums” still placed a pack loop | Style goals must not add parts. Asking Mixroom to create drums / a beat / generated audio parts → empty commands + `generated_drums`, never `sample.place` as a substitute. `sample.place` only when this request names a specific library item already in context. “Add a bassline” may create MIDI |
| Skip copy on named singles | Import/export/drums lecture on “make this louder” | Attach a skip note only when `skipped` is non-empty (this request asked and Mixroom refused). Named singles with empty `skipped` stay silent. |
| Skip codes | English scrape of `user_message` (`skip`, `won't generate`, …) | Closed `skipped` codes on PlanV3 (`import`, `export`, `generated_drums`, `binaural_8d`). App localizes. Missing/unknown codes are dropped |
| Chat receipt | System bullet list plus assistant sentence; mix listed every EQ/compressor knob | Same chat chrome as before: system execution list plus assistant sentence. Mix stays an intent line. No Play/Undo chips. The floating “Applied N changes” toast is **kept**. Verified applies store `undo_record_id` on the chat message; per-bubble Undo must undo that record only when it is still the current stack top |
| Stale selection | Invalid primary clip could fail snapshot building | Invalid primary clip / clip indices are dropped instead of failing the plan |

### Code map

| File | Role |
| --- | --- |
| `lib/ai/v3/ai_v3_style_compiler.dart` | Always-on compiler + align-collapse retry from `goal_kind` |
| `lib/ai/v3/ai_v3_contract.dart` | PlanV3 `goal_kind` enum and optional `skipped` codes |
| `lib/ai/chat_pipeline.dart` | Receipt text, skip attach from codes, mix-detail collapse |
| `lib/ai/v3/ai_v3_automation_targets.dart` | Always-on pan/gain targets; strip pan from mix when a sweep exists |
| `lib/ai/v3/ai_v3_planner_request.dart` | Injects planner + compiler into `instructions` for proxy and direct OpenAI |
| `lib/ai/v3/ai_v3_adaptive_midi_planner.dart` | Same compiler on adaptive first-shot and continuation (direct OpenAI) |
| `lib/ai/v3/ai_v3_planner_service.dart` | One align-collapse retry; retry reminder goes in `instructions` |
| `lib/ai/v3/ai_v3_preparer.dart` | Mix pan-intent strip at prepare time |
| `lib/ai/v3/ai_v3_context.dart`, `ai_v3_planning_snapshot.dart` | Automation targets + stale selection |
| `lib/screens/audio_editor.dart` | Verified apply still inserts the system execution list plus assistant sentence; no extra action chips |

## Behavior: before vs after

Project under test: one vocal/instrumental audio clip unless noted.
Live runs used macOS Mixroom with
`flutter run -d macos --dart-define-from-file=tool/local_ai_debug.json`.

| Prompt | Before | After (live) |
| --- | --- | --- |
| `make this louder` | Gain up; sometimes skip lecture | **+3 dB only.** One receipt. No skip lecture |
| `chipmunk this` | Could become full nightcore (tempo + mix) | **Pitch only** (live: +12). Compiler now asks for a moderate default |
| `orbit in headphones` | Missing pan target, or mix-widen instead of a sweep | **10 pan points**, no mix-widen |
| `make this a nightcore remix` | Tempo-align only, or stacked extra pitch | **150 BPM, +3 pitch, brighter EQ**, one row. No import/drums/export |
| `make this a garage remix` | Invented library drums; future-tense skip copy | **132 BPM + compressor/EQ**, no drums. Skip codes, not English scrape |
| `add a bassline` | Inconsistent | **MIDI row + 32-note clip** (explicit arrangement) |
| `add nightcore drums` | Placed library loops, or timed out at 25s | Out of product: empty commands + `skipped: generated_drums`. Compiler now forbids `sample.place` as a substitute. Re-test live after hot restart |
| `what is nightcore?` | Should not mutate | Unchanged: question, no edits |

Unsupported on purpose (say so, do not fake it): import, export, generated
drums, true binaural 8D / HRIR.

## Experiments

### Lab 1 — Pre-fix live (2026-08-21, ~17:54–18:07)

16 prompts against a live project. **13 pass, 2 partial, 1 fail (88%).**

- Fail: explicit “add nightcore drums” placed library loops.
- Partial: chipmunk → full nightcore stack.
- Partial: slowed + reverb stacked extra pitch.

### Lab 2 — Post-compiler live (2026-08-21, ~19:03–19:11)

Six held-out / regression prompts. **6/6 pass.**

Louder, chipmunk, orbit, nightcore, garage, add bassline — results in the
table above.

### Lab 3 — UX pass (chat chrome kept as before)

After Lab 2, mix receipts dumped every EQ/compressor knob. That pass
kept the existing chat layout and only changed copy:

1. Mix `mix.apply_goal` details collapsed to the receipt intent.
2. Skip notes come from PlanV3 `skipped` codes, localized by the app.
3. Moderate pitch-only metaphor wording in the compiler.

Verified apply still shows the system execution list plus the assistant
sentence. Play/Undo chips were tried and removed so the chat UI matches
pre-PRO-16. The bottom toast “Applied N changes” stays.

## Automated tests

Use `flutter test`, not `dart test`.

```bash
flutter test \
  test/ai_v3_style_compiler_test.dart \
  test/ai_v3_automation_targets_test.dart \
  test/ai_v3_planning_snapshot_test.dart \
  test/ai_v3_context_test.dart \
  test/ai_v3_contract_test.dart \
  test/ai_v3_planner_service_test.dart \
  test/assistant_action_flow_test.dart \
  test/editor_undo_capture_test.dart
```

Coverage includes: compiler has no genre names or hardcoded +3 / 1.25×;
nightcore / phonk / set-tempo / questions share identical instructions;
proxy and direct-OpenAI payloads both send the compiler in `instructions`;
align-collapse retries only `production_goal` align-only plans, not
`named_edit`; pan targets always
present; mix pan stripped when a sweep exists; skip notes omitted on named
singles; skip notes come from `skipped` codes; generated-drum asks must not
use `sample.place` as a substitute; mix execution details
collapse to intent; verified AI undo is bound to that apply’s record id.

## Manual integration checklist

Replay on macOS with a project that already has audio:

1. `make this louder` — gain only; one chat bubble; toast OK.
2. `chipmunk this` — pitch only.
3. `orbit in headphones` — pan automation, no widen.
4. `make this a nightcore remix` — faster + higher + brighter; no new drums.
5. `make this a garage remix` — groove/mix; no invented drums; skip codes.
6. `add a bassline` — may create MIDI.
7. `add nightcore drums` — no new row; skip note for generated drums; fast.
8. Named pack item already in context — may `sample.place`.
9. `what is nightcore?` — no mutation.
10. Cmd+Z after two AI applies — undoes only the latest apply, not the older bubble.
11. Per-bubble Undo, if re-added, must use that message’s `undo_record_id` and stay disabled when a newer change is on top.

## Out of scope

- ChatGPT import / invented drums / true 8D / master / export.
- Genre regex catalogs and hardcoded BPM/pitch recipes.
- [PRO-51](https://linear.app/mixroom/issue/PRO-51/macos-opening-a-project-hangs-on-opening-project) project-open hang.
- Linear status moves (tickets remain In Progress until review).

## Update trigger

Update this page when the compiler instructions, align-collapse retry,
automation-target guarantee, mix pan-strip, skip-note policy, or verified
chat receipt / undo-record binding changes.
