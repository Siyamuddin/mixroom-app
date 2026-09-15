#!/usr/bin/env python3
"""Retrain both ONNX refinement models from observed human choices and adjustments."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import shutil
from human_magnitude_data import extract, extract_historical
from human_selection_data import extract_selection
from common.mix_selection_contract import CONTRACT as SELECTION_CONTRACT, FEATURE_COUNT as SELECTION_FEATURE_COUNT, features as selection_features
from common.mix_magnitude_contract import CONTRACT, FEATURE_COUNT, features, fingerprint


def train(rows, output, *, classifier, development=False, historical_groups=(), selection_rows=None):
    import numpy as np
    import onnx
    import onnxruntime as ort
    from sklearn.ensemble import GradientBoostingRegressor
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import StandardScaler
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType
    output = Path(output)
    if output.exists(): raise ValueError('Choose a new output directory')
    if not rows: raise ValueError('No eligible continuous producer decisions')
    seen = set(); groups = {}
    for row in rows:
        if row['id'] in seen: raise ValueError('Duplicate training decision')
        seen.add(row['id'])
        if groups.setdefault(row['group'], row['split']) != row['split']: raise ValueError('Song leaks across splits')
        if row['features'] != features(row['state_before'], row['descriptor'], row['scope'], row['direction']): raise ValueError('Training/runtime feature mismatch')
        if not np.isfinite(row['target']) or not 0 <= row['target'] <= 1: raise ValueError('Invalid normalized human amount')
    fit = rows if development else [r for r in rows if r['split'] == 'train']
    fit_groups = {r['group'] for r in fit}
    if not development:
        if len(fit) < 100 or len(fit_groups) < 10: raise ValueError('Normal training requires 100 continuous decisions from 10 training songs')
        if not set(historical_groups) & fit_groups: raise ValueError('Include reviewed original training captures before replacing the magnitude model')
        for kind in ('gain', 'pan', 'parameter'):
            if len({r['group'] for r in fit if r['descriptor']['kind'] == kind}) < 3:
                raise ValueError(f'Need {kind} coverage from three training songs')
        for split in ('validation', 'test'):
            if len({r['group'] for r in rows if r['split'] == split}) < 10: raise ValueError(f'Need 10 independent {split} songs')
    selection_rows = selection_rows or []
    choices = selection_rows if development else [r for r in selection_rows if r['split'] == 'train']
    if set(r['label'] for r in choices) != {0, 1}:
        raise ValueError('Classifier training needs both retained and observed rejected/reverted decisions; do not invent negatives')
    selection_seen = set()
    for row in selection_rows:
        if row['id'] in selection_seen: raise ValueError('Duplicate classifier example')
        selection_seen.add(row['id'])
        if row['label'] not in (0, 1): raise ValueError('Invalid classifier label')
        if groups.setdefault(row['group'], row['split']) != row['split']: raise ValueError('Song leaks between classifier and magnitude splits')
        if row['features'] != selection_features(row['state_before'], row['descriptor'], row['scope'], row['direction'], row['choice'], row['goal']):
            raise ValueError('Classifier training/runtime feature mismatch')
    if not development:
        if len(choices) < 100 or len({r['group'] for r in choices}) < 10:
            raise ValueError('Classifier needs 100 observed decisions from 10 training songs')
        for label in (0, 1):
            if len({r['group'] for r in choices if r['label'] == label}) < 3:
                raise ValueError('Classifier needs retained and rejected decisions from at least three training songs each')
        for split in ('validation', 'test'):
            selected = [r for r in selection_rows if r['split'] == split]
            if any(len({r['group'] for r in selected if r['label'] == label}) < 10 for label in (0, 1)):
                raise ValueError(f'Classifier {split} needs each class across 10 independent songs')
    fit_groups |= {r['group'] for r in choices}
    choice_counts = Counter(r['group'] for r in choices)
    choice_weights = [r['weight'] * len(choices)/(len(choice_counts)*choice_counts[r['group']]) for r in choices]
    cx = np.asarray([r['features'] for r in choices], dtype=np.float32)
    cy = np.asarray([r['label'] for r in choices], dtype=np.int64)
    classifier_model = Pipeline([('scaler', StandardScaler()), ('clf', LogisticRegression(
        random_state=42, solver='liblinear', class_weight='balanced', max_iter=1000))])
    classifier_model.fit(cx, cy, clf__sample_weight=choice_weights)
    classifier_artifact = convert_sklearn(classifier_model,
        initial_types=[('features',FloatTensorType([None, SELECTION_FEATURE_COUNT]))], target_opset=17,
        options={id(classifier_model.named_steps['clf']): {'zipmap':False}})
    choice_controls = {fingerprint(r['descriptor']):r['descriptor'] for r in choices}
    choice_support = {k:len({r['group'] for r in choices if fingerprint(r['descriptor'])==k}) for k in choice_controls}
    onnx.helper.set_model_props(classifier_artifact, {'mix_feature_contract_version':SELECTION_CONTRACT,
        'output_contract':'observed_action_acceptance_v1','development_only':str(development).lower(),
        'control_contracts':json.dumps(choice_controls,separators=(',',':')), 'control_song_counts':json.dumps(choice_support),
        'training_group_ids':json.dumps(sorted(fit_groups))})
    onnx.checker.check_model(classifier_artifact)
    classifier_session=ort.InferenceSession(classifier_artifact.SerializeToString(),providers=['CPUExecutionProvider'])
    test_cx=np.asarray([r['features'] for r in selection_rows],dtype=np.float32)
    probabilities=classifier_session.run(None,{'features':test_cx})[1][:,1]
    if not np.allclose(probabilities,classifier_model.predict_proba(test_cx)[:,1],atol=1e-5,rtol=1e-5):
        raise ValueError('Classifier ONNX export differs from sklearn predictions')
    # Equal total weight per song, so repeated sessions do not dominate training.
    counts = Counter(r['group'] for r in fit)
    weights = [(0.5 if r['source'] == 'historical_final_snapshot' else 1.0) * len(fit) / (len(counts) * counts[r['group']]) for r in fit]
    x = np.asarray([r['features'] for r in fit], dtype=np.float32)
    y = np.asarray([r['target'] for r in fit], dtype=np.float32)
    model = Pipeline([('scaler', StandardScaler()), ('reg', GradientBoostingRegressor(
        random_state=42, n_estimators=100, max_depth=3, min_samples_leaf=2, loss='squared_error'))])
    model.fit(x, y, reg__sample_weight=weights)
    artifact = convert_sklearn(model, initial_types=[('features', FloatTensorType([None, FEATURE_COUNT]))], target_opset=17)
    controls = {fingerprint(r['descriptor']): r['descriptor'] for r in fit}
    song_counts = {k: len({r['group'] for r in fit if fingerprint(r['descriptor']) == k}) for k in controls}
    onnx.helper.set_model_props(artifact, {'mix_feature_contract_version': CONTRACT,
        'output_contract': 'normalized_human_amount_v1', 'development_only': str(development).lower(),
        'control_contracts': json.dumps(controls, separators=(',', ':')),
        'control_song_counts': json.dumps(song_counts), 'training_group_ids': json.dumps(sorted(fit_groups))})
    onnx.checker.check_model(artifact)
    session = ort.InferenceSession(artifact.SerializeToString(), providers=['CPUExecutionProvider'])
    check_x = np.asarray([r['features'] for r in rows], dtype=np.float32)
    actual = session.run(None, {'features': check_x})[0].reshape(-1)
    if not np.allclose(actual, model.predict(check_x), atol=1e-5, rtol=1e-5): raise ValueError('ONNX export differs from sklearn predictions')
    # Both artifacts belong to this training run. Keep the original classifier
    # digest for audit only; no frozen classifier is stacked into the graph.
    classifier = Path(classifier)
    output.mkdir(parents=True)
    apply_path = output / 'mix_apply_classifier.onnx'
    apply_path.write_bytes(classifier_artifact.SerializeToString())
    magnitude_path = output / 'mix_magnitude_regressor.onnx'; magnitude_path.write_bytes(artifact.SerializeToString())
    report = {'feature_contract': CONTRACT, 'feature_count': FEATURE_COUNT,
        'output_contract': 'normalized_human_amount_v1', 'development_only': development,
        'models': {'apply': apply_path.name, 'magnitude': magnitude_path.name},
        'model_sha256': {k: hashlib.sha256((output/n).read_bytes()).hexdigest() for k,n in {'apply': apply_path.name,'magnitude':magnitude_path.name}.items()},
        'classifier_retrained': True, 'classifier_feature_contract': SELECTION_CONTRACT,
        'classifier_feature_count': SELECTION_FEATURE_COUNT, 'classifier_examples':len(choices),
        'classifier_classes':dict(Counter(r['label'] for r in choices)),
        'classifier_source_coverage':dict(Counter(r['source'] for r in choices)),
        'baseline_classifier_sha256':hashlib.sha256(classifier.read_bytes()).hexdigest(),
        'training_group_ids': sorted(fit_groups), 'training_examples': len(fit),
        'historical_training_groups': sorted(set(historical_groups) & fit_groups),
        'action_coverage': dict(Counter(r['descriptor']['kind'] for r in fit)),
        'source_coverage': dict(Counter(r['source'] for r in fit)),
        'onnx_runtime_parity': 'passed', 'training_runtime_feature_parity': 'passed',
        'held_out_improvement_proven': False, 'publication_approved': False}
    (output / 'training_manifest.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def review(files, output, *, classifier, development=False, historical_files=(), train_requested=True, group_map=None):
    output = Path(output); output.mkdir(parents=True, exist_ok=False)
    examples = {}; selection_examples = {}; exclusions = Counter(); selection_exclusions = Counter(); sources = []; historical_groups = set()
    historical_files = {Path(p).resolve() for p in historical_files}
    for path in sorted({Path(p).resolve() for p in files} | historical_files):
        raw = path.read_bytes(); document = json.loads(raw)
        if group_map:
            source = str(document.get('source_group_ref') or document.get('project_ref') or document.get('project_id') or '')
            if source not in group_map or not isinstance(group_map[source], str) or not group_map[source]:
                raise ValueError('Group map must cover every input project identity')
            if document.get('schema_version') in (3, '3'): document['project_id'] = group_map[source]
            else: document['source_group_ref'] = group_map[source]
        rows, skipped = (extract_historical(document) if path in historical_files and document.get('schema_version') in (3, '3') else extract(document)); exclusions.update(skipped)
        for row in rows:
            if row['id'] in examples and examples[row['id']] != row: raise ValueError('Conflicting duplicate capture')
            examples[row['id']] = row
            if path in historical_files: historical_groups.add(row['group'])
        selected, reasons = extract_selection(document, historical=path in historical_files and document.get('schema_version') in (3,'3'))
        selection_exclusions.update(reasons)
        for row in selected:
            if row['id'] in selection_examples and selection_examples[row['id']] != row: raise ValueError('Conflicting duplicate classifier evidence')
            selection_examples[row['id']] = row
        sources.append({'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest(), 'continuous_decisions':len(rows)})
    rows = list(examples.values())
    selection_rows = list(selection_examples.values())
    (output/'selection_examples.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in selection_rows))
    (output/'examples.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
    report = {'examples':len(rows), 'songs':len({r['group'] for r in rows}),
        'by_kind':dict(Counter(r['descriptor']['kind'] for r in rows)),
        'by_session':dict(Counter(r['session_id'] for r in rows)), 'exclusions':dict(exclusions),
        'sources':sources, 'historical_songs':len(historical_groups), 'improvement_proven':False,
        'classifier_examples':len(selection_rows), 'classifier_labels':dict(Counter(r['label'] for r in selection_rows)),
        'classifier_exclusions':dict(selection_exclusions)}
    if train_requested:
        try: report['training'] = train(rows, output/'models', classifier=classifier, development=development, historical_groups=historical_groups,selection_rows=selection_rows)
        except ValueError as exc: report['training_error'] = str(exc)
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def paths(values):
    files=[]
    for value in values:
        p=Path(value).expanduser()
        files.extend(sorted(set(p.rglob('session*.json')) | set(p.rglob('bundle.json'))) if p.is_dir() else [p])
    return files


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('paths', nargs='+');p.add_argument('--output', required=True, type=Path)
    p.add_argument('--baseline-classifier', '--classifier', dest='classifier', help='Original classifier file for provenance only; both models are retrained', type=Path, default=Path(__file__).resolve().parents[1]/'llm_proxy/src/models/mix_apply_classifier_official_sessions_20260330_seed1.onnx')
    p.add_argument('--historical-captures', nargs='*', default=[])
    p.add_argument('--development-only', action='store_true')
    p.add_argument('--group-map', type=Path, help='Map every project identity to its canonical song identity, including copies/reimports')
    args=p.parse_args()
    report=review(paths(args.paths),args.output,classifier=args.classifier,development=args.development_only,historical_files=paths(args.historical_captures),group_map=json.loads(args.group_map.read_text()) if args.group_map else None)
    print(json.dumps(report,indent=2));return 2 if 'training_error' in report else 0

if __name__=='__main__': raise SystemExit(main())
