"""Extract successful human control changes for magnitude ONNX training."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import copy
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'llm_proxy/src'))
from common.mix_magnitude_contract import CONTRACT, features, fingerprint, parameter_descriptor, encode_target, control_action, starting_value
from common.plugin_identity import canonical_plugin_id
from producer_capture_converter import _sha256, _split


def scopes(project):
    yield {'scope': 'master'}, {'gain': project.get('master_gain_0to3'), 'pan': project.get('master_pan_0to1'), 'effects': project.get('master_effects', [])}
    for row in project.get('rows', []):
        yield {'scope': 'row', 'row': row['row'], 'row_id': row.get('row_id'), 'force_individual_row': True}, {'gain': row.get('mix', {}).get('gain_0to3'), 'pan': row.get('mix', {}).get('pan_0to1'), 'effects': row.get('effects', [])}
    for bus in project.get('group_buses', []):
        representative = next((r for r in project.get('rows', []) if r.get('group_id') == bus.get('group_id')), None)
        if representative:
            yield {'scope': 'row', 'row': representative['row'], 'row_id': representative.get('row_id'), 'group_id': bus['group_id'], 'force_individual_row': False}, bus


def scope_key(scope):
    return (scope['scope'], scope.get('row_id'), scope.get('group_id'))


def extract(bundle, *, include_discrete=False):
    rows, exclusions = [], Counter()
    if bundle.get('schema_version') != 'producer_training_capture_v4' or not bundle.get('consent_version') or not bundle.get('ended_at'):
        return rows, Counter({'unsupported_or_open_capture': 1})
    group = bundle.get('source_group_ref') or (bundle.get('project_ref') if bundle.get('segmentation_version') == 'natural_action_burst_v2' else None)
    if not group: return rows, Counter({'missing_stable_song_group': 1})
    group = _sha256(group)
    for episode in bundle.get('episodes', []):
        if episode.get('producer_outcome') != 'accepted' or (episode.get('provenance') or {}).get('label') != 'producer':
            exclusions['outcome_not_confirmed_good'] += 1; continue
        if episode.get('status') != 'complete' or episode.get('capture_warning') or (episode.get('outcome_signals') or {}).get('undo_redo_observed'):
            exclusions['ambiguous_or_incomplete_episode'] += 1; continue
        before = episode.get('state_before', {}).get('project_state', {})
        after = episode.get('state_after', {}).get('project_state', {})
        before_scopes = list(scopes(before)); after_scopes = list(scopes(after))
        before_keys = Counter(scope_key(s) for s, _ in before_scopes)
        after_keys = Counter(scope_key(s) for s, _ in after_scopes)
        final_scopes = {scope_key(s): v for s, v in after_scopes}
        def add(descriptor, scope, value, origin):
            target = encode_target(descriptor, value)
            if target is None:
                exclusions['unsupported_parameter_encoding'] += 1; return
            if descriptor.get('type') != 'float' and not include_discrete:
                exclusions['discrete_action_archived_not_magnitude'] += 1; return
            discrete = descriptor.get('type') != 'float'
            start = None if descriptor['kind'] in ('insert', 'remove', 'reset') else starting_value(before, descriptor, scope)
            if not discrete and not descriptor.get('inserted') and encode_target(descriptor, start) is None:
                exclusions['missing_initial_value'] += 1; return
            direction = 0 if discrete or descriptor.get('inserted') else (1 if value > start else -1)
            magnitude = target if discrete or descriptor.get('inserted') else abs(value - start) / (descriptor['max'] - descriptor['min'])
            try: vector = features(before, descriptor, scope, direction)
            except (ValueError, TypeError, KeyError):
                exclusions['invalid_starting_context'] += 1; return
            identity = [bundle['session_id'], episode.get('episode_id'), scope, descriptor]
            rows.append({'id': fingerprint(identity), 'group': group, 'split': _split(group),
                         'session_id': bundle['session_id'], 'episode_id': episode.get('episode_id'),
                         'descriptor': descriptor, 'scope': scope, 'features': vector,
                         'target': magnitude, 'native_target': value, 'direction': direction, 'initial_value': start, 'origin': origin,
                         'source': 'ai_capture' if episode.get('inference_traces') else 'manual_capture',
                         'state_before': before, 'producer_confirmed_good': True})
        for scope, initial in before_scopes:
            if before_keys[scope_key(scope)] != 1 or after_keys[scope_key(scope)] > 1:
                exclusions['ambiguous_track_identity'] += 1; continue
            if scope.get('scope') == 'row' and scope.get('row_id') is None:
                exclusions['missing_track_identity'] += 1; continue
            final = final_scopes.get(scope_key(scope))
            if final is None:
                exclusions['track_removed_or_replaced'] += 1; continue
            for kind in ('gain', 'pan'):
                if initial.get(kind) != final.get(kind):
                    add({'kind': kind, 'type': 'float', 'min': 0.0, 'max': 3.0 if kind == 'gain' else 1.0}, scope, final.get(kind), 'settled_control_change')
            old, new = initial.get('effects', []), final.get('effects', [])
            old_by_id = {e.get('instanceId'): e for e in old}
            new_by_id = {e.get('instanceId'): e for e in new}
            if len(old_by_id) != len(old) or len(new_by_id) != len(new) or None in old_by_id or None in new_by_id or '' in old_by_id or '' in new_by_id:
                exclusions['ambiguous_plugin_identity'] += 1; continue
            for effect in new:
                if sum(str(item.get('name', '')).lower() == str(effect.get('name', '')).lower() for item in new) > 1:
                    exclusions['ambiguous_effect_selector'] += 1; continue
                previous = old_by_id.get(effect['instanceId'])
                if not effect.get('effectId') or not effect.get('name') or effect.get('isBypassed'):
                    exclusions['missing_or_bypassed_plugin'] += 1; continue
                inserted = previous is None
                if previous and (previous.get('effectId') != effect['effectId'] or previous.get('isBypassed')):
                    exclusions['plugin_contract_changed'] += 1; continue
                if inserted:
                    add({'kind': 'insert', 'effect_id': canonical_plugin_id(effect['effectId']), 'effect_name': effect['name'], 'type': 'bool'}, scope, True, 'chosen_effect')
                old_params = {p.get('id'): p for p in previous.get('parameters', [])} if previous else {}
                for parameter in effect.get('parameters', []):
                    if not parameter.get('id') or not parameter.get('name'): continue
                    prior = old_params.get(parameter['id'])
                    descriptor = parameter_descriptor(effect, parameter, inserted=inserted)
                    if not inserted:
                        if prior is None or parameter_descriptor(previous, prior) != descriptor:
                            exclusions['parameter_contract_changed'] += 1; continue
                        if prior.get('value') == parameter.get('value'): continue
                    # Inserted presets retain their full accepted configuration.
                    # Their input state contains NO inserted parameter values.
                    add(descriptor, scope, parameter.get('value'), 'chosen_preset_parameter' if inserted else 'settled_control_change')
            for effect in old:
                if effect['instanceId'] not in new_by_id and effect.get('effectId'):
                    add({'kind': 'remove', 'effect_id': canonical_plugin_id(effect['effectId']), 'effect_name': effect['name'], 'type': 'bool'}, scope, True, 'removed_effect')
            if old and not new:
                add({'kind': 'reset', 'type': 'bool'}, scope, True, 'cleared_chain')
    return rows, exclusions


def historical_bundles(bundle):
    """Import explicitly supplied v3 snapshots, retaining weaker historical provenance.

    Old files lack UUIDs and outcome ratings. Track matching requires identical
    clip signatures; builtin effects require unique, unchanged chains or a unique
    insertion. Surrogate identities are local matching keys, never captured IDs.
    """
    if bundle.get('schema_version') not in (3, '3'):
        return [], Counter({'unsupported_historical_schema': 1})
    builtin = {'EQ 3-Band', 'EQ Parametric', 'Compressor', 'Limiter', 'Clipper', 'Reverb', 'Delay', 'De-Esser', 'Distortion', 'Transient Shaper', 'Gate'}
    result=[]; excluded=Counter()
    for cycle in bundle.get('prompt_cycles', []):
        if cycle.get('status') != 'complete' or not cycle.get('producer_final_snapshot') or not cycle.get('final_captured_at'):
            excluded['historical_missing_explicit_final_snapshot'] += 1; continue
        before=copy.deepcopy(cycle.get('before_prompt_snapshot',{}).get('project_state',{}))
        after=copy.deepcopy(cycle['producer_final_snapshot'].get('project_state',{}))
        for project in (before, after):
            for row in project.get('rows',[]):
                clips=row.get('clips',[])
                row['row_id']=fingerprint(clips) if clips else None
            for chain in [project.get('master_effects',[]), *[r.get('effects',[]) for r in project.get('rows',[])]]:
                for effect in chain:
                    name=effect.get('name')
                    # Do not infer identity or ranges for opaque hosted plugins.
                    if name not in builtin or sum(e.get('name')==name for e in chain)!=1: continue
                    effect['effectId']=name
                    effect['instanceId']='historical-unique-name:'+name
        # Internal adapter only. These values describe conversion policy, not a
        # retroactive assertion that the historical file contained v4 consent.
        adapted={'schema_version':'producer_training_capture_v4', 'consent_version':'historical_explicit_operator_import',
            'ended_at':cycle['final_captured_at'], 'source_group_ref':str(bundle.get('project_id') or ''),
            'session_id':bundle['session_id'], 'episodes':[{'episode_id':cycle['cycle_id'], 'status':'complete',
            'producer_outcome':'accepted', 'provenance':{'label':'producer'},
            'state_before':{'project_state':before}, 'state_after':{'project_state':after}}]}
        if not adapted['source_group_ref']:
            excluded['historical_missing_song_identity'] += 1; continue
        adapted['episodes'][0]['historical_actions'] = copy.deepcopy(cycle.get('resolved_ai_actions', []))
        adapted['episodes'][0]['historical_goal'] = copy.deepcopy(cycle.get('llm_payload', {}).get('tool_args', {}))
        result.append(adapted)
    return result, excluded


def extract_historical(bundle, *, include_discrete=False):
    adapted_bundles, excluded = historical_bundles(bundle)
    result = []
    for adapted in adapted_bundles:
        rows, reasons = extract(adapted, include_discrete=include_discrete)
        excluded.update(reasons)
        for row in rows:
            row['source'] = 'historical_final_snapshot'
            row['producer_confirmed_good'] = False
            row['label_provenance'] = 'submitted_final_snapshot_without_outcome_rating'
            result.append(row)
    return result, excluded
