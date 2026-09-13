# Test the two ONNX refinement models locally

Capture stays the same: enable it, mix normally, stop, and give an honest outcome.
No AI prompt or particular questionnaire category is required. Nothing below uploads
or deploys data, code, or models.

## Train and run

From the repository root, with `backend/training/requirements.txt` installed:

```bash
read -r 'PRO20_CAPTURES?Recent capture folder: '
read -r 'PRO20_HISTORY?Historical capture folder: '
python backend/training/train_human_magnitude.py "$PRO20_CAPTURES" --historical-captures "$PRO20_HISTORY" --output /tmp/pro20-human-review --development-only
python backend/training/serve_local_refinement.py --model-directory /tmp/pro20-human-review/models --allow-development-model
```

The prompts above use macOS zsh. Local exports are under the project’s
`exports/producer_sessions/`. Uploaded bundles live in the configured
`PRODUCER_TRAINING_BUCKET` under `structured/user=…/session=…/bundle.json`;
session status lives in `PRODUCER_TRAINING_SESSIONS_TABLE` (DynamoDB). Download
completed bundles preserving their directory structure. The trainer discovers
both `session*.json` and `bundle.json`.

Use a new output folder for each run. Stop the previous local server first.
The report lists sources, exclusions, unique targets and song groups. Original
files remain untouched. Repeated downloads deduplicate by session/episode/control.
Inserted presets provide configuration targets, not necessarily individual knob edits.

The output contains **two ONNX files**: an unchanged copy of the classifier and a
newly trained magnitude regressor. Check `classifier_unchanged`, both parity checks,
and the model hashes in `models/training_manifest.json`. The server loads both.
There is no additional learned model or JSON estimator.

If the local-test app is already running, it uses the restarted local server.
Otherwise save/close the regular app and run:

```bash
flutter run -d macos --dart-define=MIXROOM_LOCAL_REFINE_URL=http://127.0.0.1:8765
```

1. Open a copy of a project and ask for a general balance or effect adjustment.
2. Confirm `/health` reports `mix_magnitude_human_v3`. Resolver responses should
   show `fallback_used: false` and `human_magnitude` when the control is supported.
3. Play the result. Check levels, pan and effect settings, then test undo and saving.
4. Try an unknown effect and a reset/rebuild request. Unsupported magnitude targets
   retain the proposed action; they do not trigger another model or break execution.

## What changed in the magnitude model

The classifier retains its existing input contract and weights. The second model
now uses 184 features and predicts a **normalized adjustment amount**, replacing
the old proposal multiplier. It learns continuous gain, pan and effect parameters.
For an inserted effect, it learns the accepted parameter's position in its range,
without inventing an initial setting. Categorical choices and effect add/remove
operations remain classifier/planner responsibilities and stay in the raw archive.

Runtime preserves the proposal's direction and native bounds. Existing controls
cannot exceed 3x the proposed change or a quarter of their range. Inserted settings
can move at most a tenth of the range away from the proposed setting. Classifier
confidence still attenuates changes. Unknown controls, ambiguous selectors, reset
batches, and special style/audibility requests do not receive guessed magnitudes.

The trainer fits one StandardScaler/GradientBoostingRegressor pipeline using both
new and historical data, balancing song weights. Historical submitted final states
lack explicit success ratings, so they carry weaker provenance and half weight.
Missing historical plugin identities are matched only for unique known builtins;
unsupported or ambiguous controls are reported. Old CSVs alone cannot reconstruct
these new inputs; supply the original snapshot JSONs.

This contract runs in the Python backend. Existing 77/141-feature models still
work with their original decoder. Native Dart fallback retains its existing models;
do not put the new 184-feature file in a native 77-feature model slot. A future AWS
release must deploy this decoder before enabling the new magnitude artifact.
Retraining replaces the magnitude artifact; it does not accumulate models.

## Establish improvement before promotion

Development exports deliberately allow a small corpus, train on all supplied
songs, and never count fitting error as improvement. Normal exports require at
least 100 targets across 10 training songs, reviewed historical captures, and
10 independent songs in each validation/test split. Gain, pan and effect parameters
each need examples from at least three training songs. Normal inference requires
support from three training songs per control. These checks are minimum coverage,
not a quality guarantee. Keep copies/reimports of a song in one canonical group. Use `--group-map` with
a JSON object mapping every input project identity to a canonical song identity
when old/new project IDs or copied projects refer to the same song. Project groups
are only independent songs after this identity review.

Train without `--development-only` on the accumulated corpus, then evaluate:

```bash
python backend/training/evaluate_human_magnitude.py /tmp/pro20-human-review/examples.jsonl --candidate-directory /tmp/pro20-human-review/models --output /tmp/pro20-human-comparison.json
```

This tests fixed proposals on held-out songs, using the demonstrated control and
direction but never its final magnitude. Inspect error, coverage, per-action/source
results and song-level confidence intervals. It measures conditional parameter
agreement, not chat planning. The evaluator rejects candidate training-song reuse.
Historical songs may have trained the baseline; the report states that uncertainty.

For captures containing real AI proposals, also use `evaluate_producer_models.py`
against the packaged/current baseline. Finally blind-listen to old/new results
from identical starting states and requests on unseen songs. Record preferences
and further corrections. Neither parameter agreement nor the scripts authorize
publication; deploy only after both numerical review and listening support it.

```bash
python -m unittest discover -s backend/training/tests -v
python -m unittest discover -s backend/llm_proxy/tests -p '*mix_resolve*' -v
```
