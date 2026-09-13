#!/usr/bin/env python3
"""Retrain the second ONNX model from continuous human decisions; copy classifier unchanged."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import shutil
from human_magnitude_data import extract, extract_historical
from common.mix_magnitude_contract import CONTRACT, FEATURE_COUNT, features, fingerprint


def train(rows, output, *, classifier, development=False, historical_groups=()):
    import numpy as np
    import onnx
    import onnxruntime as ort
    from sklearn.ensemble import GradientBoostingRegressor
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
    # Validate the unchanged classifier before producing a two-model bundle.
    classifier = Path(classifier)
    apply_session = ort.InferenceSession(str(classifier), providers=['CPUExecutionProvider'])
    apply_contract = apply_session.get_modelmeta().custom_metadata_map.get('mix_feature_contract_version', 'mix_refine_v1')
    if apply_contract not in ('mix_refine_v1', 'mix_refine_plugins_v2'): raise ValueError('Unsupported classifier')
    output.mkdir(parents=True)
    apply_path = output / 'mix_apply_classifier.onnx'; shutil.copyfile(classifier, apply_path)
    magnitude_path = output / 'mix_magnitude_regressor.onnx'; magnitude_path.write_bytes(artifact.SerializeToString())
    report = {'feature_contract': CONTRACT, 'feature_count': FEATURE_COUNT,
        'output_contract': 'normalized_human_amount_v1', 'development_only': development,
        'models': {'apply': apply_path.name, 'magnitude': magnitude_path.name},
        'model_sha256': {k: hashlib.sha256((output/n).read_bytes()).hexdigest() for k,n in {'apply': apply_path.name,'magnitude':magnitude_path.name}.items()},
        'classifier_unchanged': apply_path.read_bytes() == classifier.read_bytes(),
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
    examples = {}; exclusions = Counter(); sources = []; historical_groups = set()
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
        sources.append({'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest(), 'continuous_decisions':len(rows)})
    rows = list(examples.values())
    (output/'examples.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
    report = {'examples':len(rows), 'songs':len({r['group'] for r in rows}),
        'by_kind':dict(Counter(r['descriptor']['kind'] for r in rows)),
        'by_session':dict(Counter(r['session_id'] for r in rows)), 'exclusions':dict(exclusions),
        'sources':sources, 'historical_songs':len(historical_groups), 'improvement_proven':False}
    if train_requested:
        try: report['training'] = train(rows, output/'models', classifier=classifier, development=development, historical_groups=historical_groups)
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
    p.add_argument('--classifier', type=Path, default=Path(__file__).resolve().parents[1]/'llm_proxy/src/models/mix_apply_classifier_official_sessions_20260330_seed1.onnx')
    p.add_argument('--historical-captures', nargs='*', default=[])
    p.add_argument('--development-only', action='store_true')
    p.add_argument('--group-map', type=Path, help='Map every project identity to its canonical song identity, including copies/reimports')
    args=p.parse_args()
    report=review(paths(args.paths),args.output,classifier=args.classifier,development=args.development_only,historical_files=paths(args.historical_captures),group_map=json.loads(args.group_map.read_text()) if args.group_map else None)
    print(json.dumps(report,indent=2));return 2 if 'training_error' in report else 0

if __name__=='__main__': raise SystemExit(main())
