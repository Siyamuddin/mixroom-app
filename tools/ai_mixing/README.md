# AI Mixing Magnitude Pipeline

This folder contains an end-to-end offline pipeline for training learned magnitude models from producer-captured sessions.

## Inputs
- Session JSON files exported by in-app Producer Data Mode (`/producer on`).
- Each session includes:
  - `ai_step` events with prompt, pre/post snapshots, LLM payload, resolved actions.
  - `manual_edit` events capturing producer corrections.

## Producer Tutorial (How to Create Good Training Data)
This section is for the music producer who is generating labeled examples.

Detailed handoff SOP (English/Korean): `tools/ai_mixing/producer_SOP.md`

### Goal
For each prompt, let AI apply its mix action first, then manually correct it to the level you consider professionally right.  
Your manual correction becomes the supervision signal for magnitude learning.

### In-app Workflow
1. Open a project and prepare your monitoring chain (normal studio workflow).
2. Turn on **Producer Capture** using the toggle in the capture toolbar above the chat bar.
3. Enter a mixing prompt in chat (example: “tighten bass and reduce boom”).
4. Let AI apply changes.
5. Manually adjust any parameters needed until it sounds right to you.
6. Export current capture using the **Export** button in that toolbar.
7. Continue with more prompts in same project, or turn off **Producer Capture**.

Optional fallback (still supported): `/producer on|off|export`

### What Gets Captured
- Pre-step snapshot (project state before AI action)
- Prompt text
- AI resolved actions (exact values applied)
- Manual producer edits after AI action
- Post-step snapshot (state after your edits)
- Optional quality rating

### Data Quality Guidelines (Important)
- Use diverse source quality: clean stems, rough recordings, different genres.
- Keep prompts realistic and varied (tone, balance, dynamics, space, polish).
- Correct both over-processing and under-processing.
- Include some “no change needed” cases when appropriate.
- Avoid rushed edits; commit only when you would ship the result.

## Output Models
- `mix_apply_classifier.onnx` (Stage 1: whether to apply / suppress)
- `mix_magnitude_regressor.onnx` (Stage 2: magnitude scale)

These are consumed by the app via `OnnxMixingMagnitudePredictor`.

## Quick Start
1. Install Python deps:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r tools/ai_mixing/requirements.txt
```

### One-command pipeline
Run full pipeline in order (`prepare -> validate -> train -> evaluate -> export`):
```bash
bash tools/ai_mixing/run_all.sh \
  --sessions-dir /path/to/ai_mixing_sessions \
  --copy-assets
```

Options:
- `--out-root tools/ai_mixing/out_custom`
- `--seed 42`
- `--test-size 0.2`
- `--skip-pip` (if deps already installed)

Examples:
```bash
# Basic
bash tools/ai_mixing/run_all.sh \
  --sessions-dir /Users/you/Library/Application\ Support/.../ai_mixing_sessions

# Build and copy ONNX directly into app assets
bash tools/ai_mixing/run_all.sh \
  --sessions-dir /Users/you/Library/Application\ Support/.../ai_mixing_sessions \
  --copy-assets
```

Check script help:
```bash
bash tools/ai_mixing/run_all.sh --help
```

2. Build dataset:
```bash
python tools/ai_mixing/prepare_dataset.py \
  --sessions-dir /path/to/ai_mixing_sessions \
  --out-csv tools/ai_mixing/out/dataset.csv
```

2.5 Validate feature contract (app inference vs training scripts):
```bash
python tools/ai_mixing/validate_feature_contract.py
```

3. Train models:
```bash
python tools/ai_mixing/train.py \
  --dataset-csv tools/ai_mixing/out/dataset.csv \
  --out-dir tools/ai_mixing/out/models
```

4. Evaluate (defaults to grouped holdout split):
```bash
python tools/ai_mixing/evaluate.py \
  --dataset-csv tools/ai_mixing/out/dataset.csv \
  --model-dir tools/ai_mixing/out/models
```

5. Export ONNX:
```bash
python tools/ai_mixing/export_onnx.py \
  --model-dir tools/ai_mixing/out/models \
  --out-dir tools/ai_mixing/out/onnx
```

6. Copy model artifacts into app assets:
```bash
cp tools/ai_mixing/out/onnx/mix_apply_classifier.onnx assets/models/
cp tools/ai_mixing/out/onnx/mix_magnitude_regressor.onnx assets/models/
```
Then ensure these files are listed in `pubspec.yaml` under `flutter.assets`.

## Recommended Data Collection Protocol
- Mix across diverse genres and source quality levels.
- Capture full lifecycle:
  - AI initial pass
  - Producer manual corrections
- Include sessions where producer intentionally keeps moves subtle or rejects over-processing.
- Target at least several thousand action rows before first production rollout.

## How Training Rows Are Built
- Unit of training is action-level (one row per AI action).
- Key features include:
  - prompt-derived intent/intensity/scope
  - project snapshot features (loudness/spectral/stereo/overlap/masking proxies)
  - action context (row/master, effect operation counts)
- Labels:
  - `label_apply` (apply vs suppress)
  - `label_magnitude_scale` (how much to scale magnitude vs baseline AI move)

In simple terms:
- AI makes a move.
- Producer corrects it.
- The pipeline learns when to keep/suppress and how much to scale future moves.

## Feature Flag Rollout
- App-side inference is controlled by:
  - `MIXROOM_USE_LEARNED_MAGNITUDES`
- Keep this disabled until offline metrics and listening tests pass.
- A/B template for listening tests:
  - `tools/ai_mixing/ab_prompt_suite_checklist.md`

## Notes
- Stage 1 is a true binary classifier (`label_apply`) with probability output.
- Stage 2 regressor predicts a multiplicative scale for action magnitudes.
- Training/eval splits are leakage-safe by default:
  - grouped by `project_id` when present
  - otherwise grouped by `session_id`
  - fallback to random split only when grouping is impossible.
- Deterministic local heuristics remain the fallback path.
- The ONNX models are exported with one float input tensor shaped `[batch, 76]` to match app inference.
- Scripts enforce the 76-feature contract to prevent accidental train/inference mismatch.
- Feature vector includes static analysis aggregates (centroid/zcr/sibilance/bassiness),
  short-term dynamics (ST-RMS mean/p95/std, transient density),
  loudness/headroom proxies (true-peak, LUFS estimates, LRA, clip ratio),
  spectral texture (flatness/rolloff/slope/flux),
  stereo-field proxies (phase correlation, side/mid ratio, stereo imbalance),
  temporal activity cues (silence ratio, onset-rate),
  and additional texture cues (noise floor, spectral bandwidth),
  and overlap/masking proxies (overlap density, centroid collision, RMS pressure, role-overlap ratio, band collisions).
- `overlap_ratio_matrix` is included in `project_state` snapshots and used by both app inference and dataset prep.
- Current static-analysis path still uses mono 16k for most content metrics; stereo stats are fetched separately via lightweight native analysis.
- If data is limited, run ablations first against likely-redundant pairs (e.g. `median_silence_ratio` vs `median_st_rms_mean`).
