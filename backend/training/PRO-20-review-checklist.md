# PRO-20 reviewer checklist

## Producer

- [ ] Build the PR, allowlist your account in admin, and enable producer capture.
- [ ] With an existing compressor/EQ/reverb, ask the AI to change it. Listen for
  30 seconds, then correct one parameter. Note the original, AI and final values.
- [ ] Stop capture. Confirm the questionnaire shows the right changes, choose an
  honest outcome, and add a note. Repeat with a master plugin and a group-bus plugin.
- [ ] Also add an effect through AI and correct its parameter, including after a
  chain reset/rebuild. Keep one change,
  revert another and choose partial: the retained/reverted actions must train as
  positive/negative examples, with the correct continuous correction scale.
- [ ] Try a native plugin window, a bool/choice control, plugin bypass/reorder,
  undo/redo, and skipping feedback. Confirm the captured changes match your work.
- [ ] Close capture offline and reconnect. Confirm upload retries. Check ordinary
  chat, playback, saving and undo with capture on and off.

## Engineer: capture and upload

From the repository root, with authorized AWS credentials:

```bash
python3 -m venv /tmp/pro20-review-env
source /tmp/pro20-review-env/bin/activate
python -m pip install -r backend/training/requirements.txt
python -m unittest discover -s backend/training/tests -v
python tools/ai_mixing/validate_feature_contract.py
python backend/training/verify_producer_capture.py --verify-upload --require-eligible --require-plugin-eligible --output /tmp/pro20-review-data
```

Paste the producer's project/capture path when prompted.

- [ ] Checks pass: identical stored bytes, valid data, online/offline feature
  parity, and eligible plugin apply and magnitude examples.
- [ ] Final values and notes match the producer's record. Discrete controls have
  no magnitude label; ambiguous/replaced plugin instances have explicit exclusions.
- [ ] `episodes-*.jsonl` retains bypass/reorder/manual work even when it produces
  no eligible current-model examples.

## Engineer + producer: train and evaluate

With a sufficiently large, reviewed corpus containing independent song groups:

```bash
python backend/training/train_mix_refine_models.py /tmp/pro20-review-data/dataset --output /tmp/pro20-review-models
python backend/training/evaluate_producer_models.py --candidate-directory /tmp/pro20-review-models --output /tmp/pro20-model-comparison.json
```

- [ ] Training exports both models and reports `onnx_runtime_parity: passed`.
  A tiny smoke dataset should fail readiness; do not duplicate samples to pass.
  Each split needs real accepted/rejected plugin examples and continuous corrections.
- [ ] Follow the [compatibility guide](PRO-20-compatibility.md) to export/test the
  existing 77-feature model and import historical captures. Compare against the
  current model and the same-data 77-feature baseline; check per-action coverage
  and warm inference latency before choosing a candidate.
- [ ] Replay uses held-out groups, reports the intended candidate/current model
  versions, and improves relevant metrics without material regressions.
- [ ] On a local/staging backend, set `MIX_APPLY_MODEL_PATH` and
  `MIX_MAGNITUDE_MODEL_PATH` to the two exports, then restart it. Connect the review
  app and run a plugin mixing request. Require the new model versions,
  `mix_refine_plugins_v2`, no fallback, and the intended control changes.
- [ ] Blind-compare current/new results on unseen songs from identical starting
  states and prompts. Record preference, goal attainment and corrections needed.

Attach `verification.json`, `training_manifest.json`, the comparison report and
brief listening notes. Mark untested stages explicitly.

Current training covers proposed-action refinement, including plugins. Complete
episode archives preserve broader work for future planner training. This version
does not render audio pairs, train an autonomous mixing planner, or publish models.
