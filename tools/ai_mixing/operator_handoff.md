# Operator Handoff: From Producer Data to Deployed Model

This guide is for you (the app operator) after producers deliver session JSON data.

---

## 1) What You Should Receive

You should get:
1. A folder containing exported producer session `.json` files.
2. A short note from producer:
   - genres covered
   - rough hours worked
   - unusual issues (if any)

Recommended folder:
`/path/to/ai_mixing_sessions/`

---

## 2) Pre-Flight Checks

Before training:
1. Confirm files exist:
```bash
ls -1 /path/to/ai_mixing_sessions/*.json | head
```
2. Confirm your Python venv is active:
```bash
source .venv/bin/activate
```
3. Confirm app/training contract:
```bash
python3 tools/ai_mixing/validate_feature_contract.py
```

You should see:
`[OK] Feature contract verified (...)`

Optional quick summary before training:
```bash
python3 tools/ai_mixing/summarize_sessions.py \
  --sessions-dir /path/to/ai_mixing_sessions
```

Note:
- This collection flow is already full-project based.
- Each dataset row is an AI action extracted from a full-project snapshot, so multiple prompt cycles on one song still count as full-project supervision.

---

## 3) Run Full Pipeline (One Command)

From repo root:

```bash
bash tools/ai_mixing/run_all.sh \
  --sessions-dir /path/to/ai_mixing_sessions \
  --copy-assets
```

What this does:
1. Prepare dataset CSV
2. Validate feature contract
3. Train models
4. Evaluate models
5. Export ONNX
6. Copy ONNX into `assets/models/`

---

## 3B) Full-Project Bootstrap Path

If you do not have enough producer session JSON yet, but you do have finished
human-made Mixroom projects, use:

```bash
bash tools/ai_mixing/run_project_bootstrap.sh \
  --projects-root /path/to/mixroom_projects \
  --copy-assets
```

Use this only as a bootstrap path for internal beta. Producer-capture session
data remains the higher-quality supervision source.

---

## 4) Inspect Outputs

Check these files:
1. `tools/ai_mixing/out/dataset.csv`
2. `tools/ai_mixing/out/models/metrics.json`
3. `tools/ai_mixing/out/models/feature_manifest.json`
4. `tools/ai_mixing/out/onnx/mix_apply_classifier.onnx`
5. `tools/ai_mixing/out/onnx/mix_magnitude_regressor.onnx`

Quick metrics view:
```bash
cat tools/ai_mixing/out/models/metrics.json
```

Look for:
1. `train_rows` / `val_rows` are non-trivial
2. `apply_roc_auc` present and reasonable (if labels contain both classes)
3. `scale_mae` not extremely high relative to your prior runs

---

## 5) Basic Data Quality Sanity

Run:
```bash
python3 - <<'PY'
import pandas as pd
df = pd.read_csv("tools/ai_mixing/out/dataset.csv")
print("rows:", len(df))
print("apply_rate:", round(df["label_apply"].mean(), 4))
print("scale_mean:", round(df["label_magnitude_scale"].mean(), 4))
print("scale_std:", round(df["label_magnitude_scale"].std(), 4))
print("top_action_types:")
print(df["action_type"].value_counts().head(10))
PY
```

Red flags:
1. Very low rows (example: `< 1000` action rows for first serious model)
2. `apply_rate` near `1.0` with almost no suppress examples
3. `label_magnitude_scale` nearly constant
4. Only a tiny subset of action types represented

---

## 6) Enable in App (Internal Test)

### A. Ensure assets are listed
Uncomment in `pubspec.yaml`:
1. `assets/models/mix_apply_classifier.onnx`
2. `assets/models/mix_magnitude_regressor.onnx`

### B. Run app with learned magnitudes enabled
```bash
flutter run \
  --dart-define=MIXROOM_USE_LEARNED_MAGNITUDES=true \
  --dart-define=OPENAI_API_KEY=YOUR_KEY
```

---

## 7) Listening Evaluation Gate (Required)

Use:
`tools/ai_mixing/ab_prompt_suite_checklist.md`

Process:
1. Compare A (heuristic) vs B (learned) on same project.
2. Loudness-match before judging.
3. Complete full prompt suite.
4. Ship only if learned model wins clearly with no major failures.

Hard fail conditions:
1. Frequent clipping or distortion introduced
2. Frequent no-op when change is clearly needed
3. Repeated harsh/unnatural outputs
4. Unstable or crash behavior

---

## 8) Rollout Strategy

Recommended:
1. Internal only first (you + small trusted users)
2. Small beta cohort
3. Wider rollout after repeated A/B wins

Keep `MIXROOM_USE_LEARNED_MAGNITUDES` as a kill switch for rollback.

---

## 9) Rollback Procedure

If regression appears:
1. Turn learned model off:
   - run/build with `MIXROOM_USE_LEARNED_MAGNITUDES=false`
2. Keep previous known-good ONNX artifacts archived
3. Revert to last known-good model pair

---

## 10) Iteration Loop

After each training cycle:
1. Archive output folder:
```bash
cp -R tools/ai_mixing/out tools/ai_mixing/out_YYYYMMDD_vX
```
2. Store notes:
   - data sources used
   - metrics
   - listening outcomes
3. Decide:
   - promote model
   - collect more targeted data
   - retrain with new batch

---

## 11) Production Note

Current app requires:
`--dart-define=OPENAI_API_KEY=...`

For real production security, move LLM calls to your backend proxy and keep OpenAI keys server-side.
