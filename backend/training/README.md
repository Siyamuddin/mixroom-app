# Producer capture and model training

Use [the reviewer checklist](PRO-20-review-checklist.md) for a short walkthrough,
and [the verification guide](PRO-20-verification.md) for detailed acceptance gates.

Capture preserves structured mixing state, plugin instances and parameter
metadata, group buses, manual/AI edits, final control changes and producer feedback.
Native plugin-window changes are reconciled at capture boundaries. No rendered
audio pairs are collected; opaque plugin binary chunks are excluded from uploads.

`producer_capture_converter.py` writes two outputs:

- Candidate examples for apply/suppress decisions and gain/pan/plugin continuous
  parameter refinement. Bool/choice and structural plugin actions use apply labels,
  never magnitude labels. Missing or ambiguous targets carry explicit exclusions.
- Checksummed episode archives preserving full before/after state, traces, manual
  operations, bypass/reorder/automation and notes, including episodes with no
  eligible current-model examples. These archives do not themselves train a planner.

`train_mix_refine_models.py` trains and exports `mix_refine_plugins_v2` ONNX models:
77 legacy features plus 64 plugin-aware features. Training and server inference
share feature extraction. The server validates model metadata/dimensions and still
supports existing 77-feature models. The default exports target the remote resolver.
Use `--feature-contract mix_refine_v1` to retrain the existing 77-feature contract
for the server or local Dart predictor. Both use the historical StandardScaler +
LogisticRegression/GradientBoostingRegressor model families by default. Ridge is
an explicit experiment (`--magnitude-estimator ridge`), not a silent replacement.

Reviewed accepted/partial episodes derive labels per action from the final state:
kept corrections remain positives, reversals/reverts become negatives. Skipped or
still-experimenting episodes do not imply approval. Independent inference traces
can train in the same episode; repeated targets remain ambiguous. For an ensure
followed by a parameter edit, capture records the engine's initial parameter state
at execution. The remote plugin-aware model defers scaling until execution when
that target does not yet exist. This adds no inference request or audio-thread work.

`verify_producer_capture.py --verify-upload --require-plugin-eligible` checks real
stored bytes, ingestion, offline conversion and online feature parity, and requires
eligible plugin targets. It prompts for the capture path and performs read-only
remote checks using the operator's AWS credentials.

`evaluate_producer_models.py` compares candidate/current resolver decisions on
held-out captures, including runtime floors and actual effective parameter changes.
Review its model versions, sample counts and action coverage, then run blind
listening on unseen songs. No script publishes models or proves improved sound.

Reconvert earlier datasets to obtain plugin features and episode archives. Old
captures without plugin metadata remain archived with explicit exclusions. Keep
raw uploads immutable and group copies of the same song before splitting data.

## Existing producer data and models

The original `tools/ai_mixing/prepare_dataset.py` still reads historical captures;
the original `run_all.sh` workflow also remains available. To use historical CSVs
with the new validated trainer, follow [the compatibility guide](PRO-20-compatibility.md).
It imports original features/labels with historical provenance and can combine them
with new captures in a 77-feature dataset. Missing historical plugin metadata never
becomes fabricated 141-feature input. Migration into a v4 archive alone is not a
training conversion.

## Background producer capture: primary two-model training path

Follow [the local guide](PRO-20-local-test.md). `train_human_refinement.py` retrains
both ONNX models from actual producer choices and historical final snapshots.
The contextual classifier uses `mix_selection_human_v1` (208 inputs) to keep/drop
proposed controls. The magnitude regressor uses `mix_magnitude_human_v3` (184 inputs)
to predict bounded adjustment amounts. Shared features and plugin identity
canonicalization keep capture, training and inference compatible.

No AI prompt is required during capture. Retained choices supply positives;
observed rejected/reverted actions supply classifier counterexamples. Untouched
controls are never labeled bad. Both classes are required. Reported task categories
provide optional context; strategies/notes remain annotations. This is contextual
selection among planner candidates, not causal reasoning or a newly trained planner.

The earlier 77/141-feature commands above remain compatibility workflows for
existing artifacts and AI-trace datasets. Use original historical JSON snapshots
with the new trainer rather than filling missing CSV context with invented input.
Evaluate both selection and magnitude, then listen before production promotion.
