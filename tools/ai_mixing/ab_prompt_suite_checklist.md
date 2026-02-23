# AI Mixing A/B Prompt Suite Checklist

Use this to compare `heuristic` mode vs `learned magnitude` mode.

## Setup
- Project ID:
- Date:
- Evaluator:
- Build/version:
- Headphones/monitors:
- Loudness matched before compare: `yes/no`

## Modes
- A = heuristics (`MIXROOM_USE_LEARNED_MAGNITUDES=false`)
- B = learned model (`MIXROOM_USE_LEARNED_MAGNITUDES=true`)
- Randomized order per prompt: `yes/no`

## Prompt Suite

For each prompt, score both A and B:
- `Naturalness` (1-5)
- `Goal Match` (1-5)
- `Artifacts/Harshness` (1-5, higher is cleaner)
- `Over/Under-processing` (1-5, higher is better balanced)
- `Clipping/Headroom pass` (`pass/fail`)
- Winner (`A/B/tie`)

1. "Make this sound like a finished professional release."
2. "Make vocals sit forward but still natural."
3. "Reduce muddiness without making it thin."
4. "Add width and space, but keep center focused."
5. "Tame harsh highs and sibilance."
6. "Make drums punchier but not clicky."
7. "Make bass tighter and less boomy."
8. "Give it a modern pop polish."
9. "Make this warmer and less sterile."
10. "Make this more energetic and louder without distortion."
11. "Make this cleaner and more balanced overall."
12. "Make this more vintage and gentle."

## Failure Checks (must stay green)
- Any obvious clipping introduced: `yes/no`
- Any severe level drops or silence: `yes/no`
- Any unstable behavior or crashes: `yes/no`
- Any repeated no-op when change was clearly needed: `yes/no`

## Summary
- Total prompt wins: A =
- Total prompt wins: B =
- Ties =
- Key regressions noticed:
- Key improvements noticed:
- Ship decision (`hold / internal only / wider rollout`):
