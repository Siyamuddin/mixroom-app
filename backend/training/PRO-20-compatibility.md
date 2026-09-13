# Retraining without losing historical coverage

For background manual capture and the replacement magnitude ONNX contract, start
with [the current local guide](PRO-20-local-test.md). The 77/141-feature commands
below document compatibility with existing model artifacts and AI-trace datasets.


The regression suite exercises all 12 historical mixing action categories:
row/master gain and pan, parameter changes, effect insertion/removal and chain
resets. Continuous corrections train magnitude; discrete/structural actions train
apply/reject. Old scalar labels on effect insertion/removal had no meaningful
continuous control to adjust.

Reviewed mixed results now train per action. An unchanged/reversed parameter
becomes a negative example; retained corrections remain positives. An ensure then
adjust operation uses recorded execution-time parameter metadata for labels only.
It never inserts post-action information into inference features. Older v4 files
without that metadata remain usable for their other eligible actions.
Reset/rebuild batches also use the new instance's actual starting value, and
replacing a chain with new instances does not falsely label its reset as rejected.

## Export for the existing remote or local predictor

From the repository root, after the review guide has produced a verified dataset:

```bash
source /tmp/pro20-review-env/bin/activate
python -m pip install -r backend/training/requirements.txt
python backend/training/train_mix_refine_models.py /tmp/pro20-review-data/dataset --feature-contract mix_refine_v1 --output /tmp/pro20-review-models77
```

This exports 77-feature models using the historical preprocessing and model
families. Default 141-feature exports remain for the remote resolver. Never put
141-feature artifacts in the local predictor's 77-feature model slots.
Use the existing asset/CDN selection workflow for the two 77-feature exports;
verify their versions and successful inference on the target app before publishing.

The native integration test runs those exact exports through the real Dart
predictor and Flutter ONNX plugin, using temporary files instead of changing the
installed model selection:

```bash
python backend/training/prepare_native_model_test.py /tmp/pro20-review-models77 --output /tmp/pro20-native-model-test.json
flutter test -d macos integration_test/producer_model_compatibility_test.dart --dart-define-from-file=/tmp/pro20-native-model-test.json
```

Use the target platform's Flutter device selector for other platforms. This
checks model loading/decoding and actual refinement without fallback; it does not
render audio or establish preference over the current model.

## Import historical captures

Keep the original captures. Generate the same CSV the old pipeline used, then
import it into the validated training format. These commands prompt for the path:

```bash
source /tmp/pro20-review-env/bin/activate
python -m pip install -r backend/training/requirements.txt
read -r 'PRO20_OLD_SESSIONS?Historical producer session directory: '
python tools/ai_mixing/prepare_dataset.py --sessions-dir "$PRO20_OLD_SESSIONS" --out-csv /tmp/pro20-historical.csv
python backend/training/import_legacy_training.py /tmp/pro20-historical.csv --output /tmp/pro20-historical-data
python backend/training/train_mix_refine_models.py /tmp/pro20-historical-data --feature-contract mix_refine_v1 --output /tmp/pro20-historical-models
```

The `read` command above uses the project's macOS zsh shell. With an existing CSV,
start at the import command and pass its path. The importer validates all 77 input
values and labels, retains historical provenance, and hashes project groups into
train/validation/test splits. Readiness needs real positive/negative examples in
each split. Historical labels retain the old extractor's limitations; importing
them does not make them newly verified or reconstruct missing runtime traces.

To combine old and new data, create a JSON object mapping **every historical
project_id** to that song's v4 `source_group_ref` (or `project_ref`). Use the same
canonical group for copies/reimports, curating the v4 inputs before conversion.
Then run:

```bash
read -r 'PRO20_GROUP_MAP?Canonical song group mapping JSON path: '
python backend/training/import_legacy_training.py /tmp/pro20-historical.csv --dataset /tmp/pro20-review-data/dataset --group-map "$PRO20_GROUP_MAP" --output /tmp/pro20-combined-data
python backend/training/train_mix_refine_models.py /tmp/pro20-combined-data --feature-contract mix_refine_v1 --output /tmp/pro20-combined-models
```

The importer requires this mapping for combined datasets to prevent the same song
appearing in both training and evaluation. It copies v4 episode archives and leaves
original uploads intact. Historical rows lack the additional plugin features, so
the combined dataset deliberately exports the existing 77-feature contract.

## Compare before promotion

Train the 77-feature and 141-feature candidates on the same reviewed v4 corpus
and splits. Use `--magnitude-estimator ridge` only for a separately named experiment.
Compare each against the currently deployed model using the review guide. To
compare the plugin-aware candidate against the retrained historical architecture:

```bash
python backend/training/evaluate_producer_models.py --candidate-directory /tmp/pro20-review-models --baseline-directory /tmp/pro20-review-models77 --output /tmp/pro20-feature-comparison.json
```

The report includes per-action agreement/error and resolver latency, separating
the first call from warm calls. The training manifest identifies source groups,
model family and contracts. Use validation songs for choices and reserve test songs
for the final comparison. Runtime parity proves compatible execution; improvement
still requires held-out metrics and blind listening without material regressions.
