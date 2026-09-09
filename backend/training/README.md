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
supports existing 77-feature models. New exports target the remote resolver;
the legacy local Dart model path remains on its existing contract.

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
