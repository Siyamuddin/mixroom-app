# PRO-20 acceptance and training verification

This release captures structured mixing decisions. It does not render or upload
before/after audio pairs. Those fields remain explicitly unavailable, and the
converter excludes them from audio-result training. The 90-day media lifecycle
is infrastructure for a future renderer, not evidence that audio was collected.

## What the current models can learn

The apply classifier learns whether an auditioned AI candidate should be used,
including plugin parameter edits, insertion, removal and chain resets. The
magnitude regressor learns producer-approved continuous parameter corrections:
gain/pan and exposed plugin controls such as EQ, compression, reverb and delay,
on tracks, group buses and the master. Bool/choice controls train apply decisions;
they are never interpolated as continuous magnitudes.

New models use `mix_refine_plugins_v2`: the unchanged 77 production features plus
64 plugin/parameter/context features. The same Python implementation builds these
features offline and during server inference. The server validates ONNX contract
metadata and dimensions for both models. Existing 77-feature models still load.
Default 141-feature exports target the server resolver. The trainer also exports
77-feature models for the existing remote/local predictor using
`--feature-contract mix_refine_v1`. It preserves the historical gradient-boosting
model family. See [historical-data compatibility](PRO-20-compatibility.md).

Capture preserves plugin instances, chain positions, bypass, parameter metadata,
normalized/display values, final control changes, group state and free text.
Native plugin-window changes are reconciled at episode/session boundaries, even
without a Flutter gesture callback. Those records describe state transitions,
not the exact timing of every native gesture. The questionnaire shows actual
plugin/parameter before/after values.

The converter also writes checksummed `episodes-*.jsonl` archives containing whole
episodes. These preserve manual-only edits, bypass/reorder, automation, notes and
unsupported operations for future training. The current models refine proposed
actions; they do not train an autonomous action-planning model from these archives.
An inserted plugin's parameter correction uses `parameter_executions`, captured
after a verified parameter application, to recover its initial engine value.
`state_after_ai` preserves the auditioned state separately from the final state.
The plugin-aware resolver defers scaling to execution for newly created targets.
Missing execution metadata, ambiguous instances or unsupported targets are excluded,
not guessed. Opaque plugin binary chunks remain outside training uploads.

## Quick employee review

1. On a fresh project with audible tracks, enable capture with an allowlisted
   account, run an AI mix that changes an existing plugin, listen for 30 seconds, then
   correct one parameter. Also test a gain/pan correction.
2. Stop capture, confirm the episode summary, select a goal/strategy and explicit
   outcome, and add a note. Repeat once with feedback skipped and once with undo/redo.
3. Check normal editor exit and disabling the project setting both show review;
   chat, playback, saving and undo must still work with capture on and off.
4. Close a session offline, reconnect, and reopen the same project under the same
   account. Allow 30 seconds for retry. Another account must not upload that session.
5. Follow “Validate actual files” below with `--verify-upload --require-eligible --require-plugin-eligible`.
   Require exit code 0, verified storage/checksums, exact uploaded bytes, matching
   conversion and at least one eligible plugin apply and magnitude example. Attach
   `verification.json` and the noted control values to the PR.

Training exclusions also cover partially applied AI batches, incomplete episodes,
missing scalar values, and deleted/replaced/reordered target tracks. Capture stores
track identities separately from the unchanged inference feature input.

## Automated checks

Run from the repository root:

```bash
flutter test test/producer_data_collector_test.dart test/producer_training_upload_service_test.dart test/producer_training_contract_test.dart test/editor_undo_capture_test.dart test/ai_v3_mix_materializer_test.dart
python3 -m unittest discover -s backend/app_api/tests -p '*producer*' -v
python3 -m unittest discover -s backend/llm_proxy/tests -p '*mix_resolve*' -v
python3 tools/ai_mixing/validate_feature_contract.py
python3 -m venv /tmp/mixroom-pro20-verify-env
/tmp/mixroom-pro20-verify-env/bin/python -m pip install -r backend/training/requirements.txt
/tmp/mixroom-pro20-verify-env/bin/python -m unittest discover -s backend/training/tests -v
```

The Dart/Python integration test creates an actual collector session, observes an
AI proposal, waits past the idle boundary, adds a human correction, labels it,
sanitizes its upload document, converts it in Python and validates the dataset.
It asserts the final magnitude is 0.5 and the real goal survives sanitization.

The Python export integration test uses explicitly synthetic sessions to exercise
training, ONNX serialization, ONNX checker, and production output decoding. It
compares exported predictions with scikit-learn predictions within 1e-5.
Passing this proves compatibility on these cases, not an improvement in sound.

## Real-app test

Rebuild and launch the app from this checkout. Use a new disposable project with
at least three audible tracks, including a vocal. Use an allowlisted account and
accept capture consent. Enable the capture UI in project settings, then turn
capture on in the overlay. Keep ordinary learned refinement enabled.

Create the following sessions, turning capture off after each. Keep a written
record of the actual controls and values you change. The output lives in the
project's `exports/producer_sessions` directory.

1. **Accepted AI correction:** Ask “Make the vocal a little more prominent using
   level changes.” Alternatively use the normal one-button mix path if the
   assistant chooses a direct setter rather than the mixing model. Let the AI
   apply its changes. Listen for at least 30 seconds. Make one deliberate vocal
   gain correction and record its before/after value. Turn capture off. Identify
   the episode by its prompt/time/edit summary. Select the applicable diagnosis
   and strategy, choose “Kept: achieved my goal,” and add “PRO-20 delayed vocal
   correction” in notes. Save the response.
2. **Rejected AI result:** Run a different mixing request. If none of the changes
   helped, leave the auditioned result in place until closing capture, select
   “None of these changes helped,” and explain why. Restore the disposable
   project afterwards. Do not manufacture rejection merely to fill a class. If
   only part was useful, select “Partly achieved”; retained corrections must become
   positive per-action examples and reverted/reversed controls negative examples.
   The episode must not assign the same label indiscriminately to every action.
3. **Unknown outcome:** Make a manual pan or EQ change. Skip the questionnaire.
   It must appear in the archive without an eligible current-model apply or
   magnitude label. Taxonomy answers alone also must not count as acceptance.
4. **Undo/redo:** Make changes, undo one, then redo it. Close capture. The journal
   must contain history events, with no automatically fabricated rejection.
   Affected episodes remain conservatively excluded from current-model training.
5. **Normal exit:** Capture another short session and exit using the editor's
   back button. The questionnaire must appear before engine shutdown. Reopen the
   project and confirm the closed session remains on disk.
6. **Disable the project setting:** While capture is active, disable its project
   setting. It must run the same review/close flow and stop capture.
7. **Retry:** Disconnect networking, close a captured session, and verify local
   status becomes `retry_needed`. Reconnect and leave the editor open for at
   least 30 seconds. It must reach `uploaded`. The automated HTTP test additionally
   proves the harder failure-after-reservation case uses identical bytes and
   checksums on retry.
8. **Interruption:** In a disposable session, quit the app during capture or
   upload, then reopen the same project. Closed `uploading` sessions must retry.
   Interrupted active episodes must be marked unavailable for training, not
   silently accepted. Earlier completed episodes remain recoverable.
9. **Capture off:** Repeat ordinary chat, save, playback and undo operations with
   capture disabled. No new capture file should appear; model refinement should
   behave the same with capture enabled and disabled.

Also repeat the accepted correction with an existing compressor threshold, EQ
frequency/gain, reverb mix, a master plugin and a grouped-track bus plugin. Record
the native control values. Test a bool/choice edit separately: it can be an apply
example but must have no magnitude label. Replace a plugin with another instance
of the same name and verify the old parameter target is excluded. Reordering the
same instance must preserve parameter identity. Check native plugin-window edits
appear before the questionnaire even when you never touch a Flutter control.

For the accepted session, inspect that `inference_traces` is nonempty. A direct
parameter command that never called the learned resolver legitimately has no
trace and is archive-only. The report explains this as
`missing_exact_inference_context`; it is not a successful current-model training
sample. The trace records the complete original candidate batch, project state,
goal, strict flag, refined actions and available model versions.

Confirm `state_after` matches what you actually heard and kept. Confirm notes
survive. A single AI episode should retain the correction made after the
30-second listening interval. Missing final snapshots, reversed/zero proposals,
multiple ambiguous proposals, unconfirmed outcomes, fallback inference and
unsupported targets must produce explicit exclusions.

## Validate actual files

This command prompts for the full project folder, capture folder, or one JSON
session path. You can paste the path without editing the command:

```bash
/tmp/mixroom-pro20-verify-env/bin/python backend/training/verify_producer_capture.py --require-eligible --require-plugin-eligible --output /tmp/mixroom-pro20-local-check
```

Expected: exit code 0, `format_validation: passed`, at least one eligible apply
and magnitude example, and `online_feature_parity: passed`. The report includes
all exclusions and eligible plugin counts. Unknown/manual/undo sessions may contain zero eligible examples;
use the accepted session or the entire dedicated test project for this gate.

To verify real backend ingestion, use your normal authorized AWS credentials and
run this read-only command. It discovers the deployed bucket and table from the
production CloudFormation stack and again prompts for the same local path:

```bash
/tmp/mixroom-pro20-verify-env/bin/python backend/training/verify_producer_capture.py --verify-upload --require-eligible --require-plugin-eligible --output /tmp/mixroom-pro20-upload-check
```

For each local session it requires exactly one structured storage object, a
verified backend row, matching stored checksums/size, byte-for-byte equality with
the frozen local `.json.payload` file, and identical local/server conversion.
It also validates the resulting sharded dataset. Run against a dedicated project
or an individual newly uploaded session; old sessions lack the frozen payload.
`--stack` and `--region` override the production defaults for staging.

Share `/tmp/mixroom-pro20-upload-check/verification.json` plus your written
before/after control values for review. The report contains IDs/counts/exclusions,
not audio, prompts or notes. Keep the source session and `.payload` together for
local diagnosis. Do not alter a frozen upload; create a new session instead.

Older local sessions without `local_owner_ref` remain archived and will not upload
automatically. Do not assign them to whoever happens to be signed in. Use newly
captured sessions for this review; owner confirmation/migration of older files
requires separate handling. The account reference remains local and is omitted
from uploaded payloads.

## Training readiness is a separate gate

A tiny smoke dataset should pass format validation but fail readiness. To check
readiness after collecting a representative corpus, first build it with the
converter, then run the trainer with `--validate-only --require-ready`.

The trainer requires at least 100 eligible examples in each objective's training
split and nonempty validation/test splits. Apply needs both classes in every
split. Each split also needs accepted/rejected plugin examples and at least one
continuous plugin correction; a level-only dataset cannot pass plugin readiness. These are plumbing minima, not a claim that 100 examples are sufficient
for a useful model. Every shard checksum, byte count, example count, feature
contract, vector value, label range, weight, ID and group split is validated.

Source groups use stable project hashes across new v2 capture sessions. Copies
or reimports of the same song with new project IDs must receive a common
`source_group_ref` in a curated offline input copy before conversion. Keep raw
uploads immutable. Without that curation, song-copy leakage remains possible.
Legacy session-salted references do not qualify automatically.

For the dataset created by the real-upload verification above:

```bash
/tmp/mixroom-pro20-verify-env/bin/python backend/training/train_mix_refine_models.py /tmp/mixroom-pro20-upload-check/dataset --output /tmp/mixroom-pro20-reviewed-models --validate-only --require-ready
/tmp/mixroom-pro20-verify-env/bin/python backend/training/train_mix_refine_models.py /tmp/mixroom-pro20-upload-check/dataset --output /tmp/mixroom-pro20-reviewed-models
```

Use a fresh output directory for each trained model. The trainer exports plugin-aware models,
checks ONNX runtime parity, and reports validation/test scores against simple
always-accept and unchanged-magnitude baselines. It does not publish models.
Model publication requires separate approval after reviewing these results.

Before claiming improvement, compare the trained and current models on unseen
songs/prompts with randomized blind listening. Record preference, goal attainment,
required correction and time-to-acceptable-result. Keep loudness controlled when
judging tone/space; assess requested loudness changes separately. Report confidence
intervals and results by genre/action type. Do not tune on the test songs.

Deletion of raw sessions does not remove examples from an already exported
training dataset or an already trained model. Rebuild affected datasets and
retrain before publishing replacements; exported examples retain session IDs to
support that process.

## Compare the candidate with the current model

After training, replay held-out captures through both production resolver paths:

```bash
/tmp/mixroom-pro20-verify-env/bin/python backend/training/evaluate_producer_models.py --candidate-directory /tmp/mixroom-pro20-reviewed-models --output /tmp/mixroom-pro20-comparison.json
```

Paste the corpus/capture path when prompted. The evaluator uses only test-split
source groups by default, rejects candidate training groups, requires successful
inference, and reports apply agreement and effective correction error by action
type. The baseline uses currently configured or packaged models; verify the
reported versions. `--baseline-directory` can select a prior trainer output.
Use `--split validation` during tuning. An empty holdout is a failure, not a reason
to evaluate training examples. This replay does not render or compare sound.

On a local/staging backend that can access the exported files:

```bash
export MIX_APPLY_MODEL_PATH=/tmp/mixroom-pro20-reviewed-models/mix_apply_classifier_producer_capture.onnx
export MIX_MAGNITUDE_MODEL_PATH=/tmp/mixroom-pro20-reviewed-models/mix_magnitude_regressor_producer_capture.onnx
export MIX_MODEL_BUNDLE_VERSION=pro20-plugin-review
```

Restart that backend, connect the review app to it, and run a plugin mixing request.
Require `mix_feature_contract_version: mix_refine_plugins_v2`, bundle version
`pro20-plugin-review`, no fallback, and the intended audible/control changes.
Then perform the blind listening comparison described above. Passing the export,
replay and runtime checks proves tested compatibility, not audible improvement.
