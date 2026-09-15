# AI Mixing Magnitude Pipeline

This folder contains an end-to-end offline pipeline for training learned magnitude models from producer-captured sessions.

For automatic PRO-20 capture, use the [current training guide](../../backend/training/README.md).
The scripts here retain historical producer-capture support. The
[compatibility guide](../../backend/training/PRO-20-compatibility.md) explains how
to import that data into the validated trainer and export the existing 77-feature models.

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
6. Press the new **Capture Final** button in the capture toolbar when that prompt cycle is done.
7. Export current capture using the **Export** button in that toolbar.
8. Continue with more prompts in same project, or turn off **Producer Capture**.

Optional fallback (still supported): `/producer on|off|export`

### What Gets Captured
- One explicit `prompt_cycle` record per prompt
- `before_prompt_snapshot` (project state before AI action)
- Prompt text
- AI resolved actions (exact values applied)
- `ai_after_snapshot` (state immediately after AI actions)
- `producer_final_snapshot` (state when producer presses **Capture Final**)
- Optional `manual_edits_debug` telemetry for troubleshooting, not primary labels
- Optional quality rating
- Session-level project metadata (`project_id`, `project_name`) on new exports

### Why the Final Capture Matters
- Raw manual edit logs are noisy because they include exploratory tweaks, bypass toggles, and repeated drags.
- The final snapshot lets dataset prep compare the AI-applied state against the producer-final state for that prompt cycle.
- Exporting, disabling Producer Capture, or starting the next AI prompt now auto-finalizes any unfinished prompt cycle so the boundary is not lost.

### Full-Project Collection Note
- This pipeline is already designed for full songs/projects, not isolated one-by-one stem labels.
- Each training row is one AI action, but its features come from the full `project_state` snapshot captured at that moment.
- Practical implication: one full project can yield many supervised rows if you run several realistic prompt cycles on it.
- Fast internal-beta target:
  - 10-20 full projects
  - 5-10 prompt cycles per project
  - roughly 5-15 resolved actions per prompt cycle
  - expected yield: about 250-1500 action rows
- That is enough for a credibility test and internal beta gate, but not a final production-quality model.

### Finished Project Bootstrap Option
If you already have finished Mixroom projects made by humans, but you do not
have enough producer-capture session JSON yet, you can bootstrap a dataset
directly from those saved project files:

```bash
bash tools/ai_mixing/run_project_bootstrap.sh \
  --projects-root /path/to/mixroom_projects \
  --copy-assets
```

What this does:
- reads project folders or `.mixroom` bundles
- mines final row/master gain, pan, and FX state as human end-state labels
- generates negative examples from actions/effects that are absent
- writes a trainable dataset CSV and exports ONNX

Important:
- this is a fast bootstrap from human-finished full projects
- it is weaker than true producer-capture session data because prompt intent and
  correction trajectory are reconstructed from end-state only
- it is still more defensible than pure synthetic placeholder data for internal beta

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

### Bootstrap sample model for app-flow testing
If you want to test the real ONNX runtime path before producer data is ready,
you can generate a synthetic bootstrap model:

```bash
.venv/bin/python tools/ai_mixing/build_bootstrap_sample_model.py --copy-assets
```

This writes a synthetic dataset, trains both sklearn stages, exports ONNX, and
copies the resulting files into `assets/models/`.

Important:
- this is only for end-to-end app testing
- it is not a production-quality mixing model
- keep `MIXROOM_USE_LEARNED_MAGNITUDES` off for real users until listening tests pass

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

2.2 Preview collection progress before training:
```bash
python tools/ai_mixing/summarize_sessions.py \
  --sessions-dir /path/to/ai_mixing_sessions
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
- Producer corrects it and marks when that prompt cycle is finished.
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
- The ONNX models are exported with one float input tensor shaped `[batch, 77]` to match app inference.
- Scripts enforce the 77-feature contract to prevent accidental train/inference mismatch.
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
