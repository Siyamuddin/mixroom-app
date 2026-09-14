"""Shared coordinates for the second ONNX model: normalized human adjustment amounts."""
from __future__ import annotations
import copy
import hashlib
import json
import math
from .plugin_identity import model_plugin_id, supported_descriptor
from .mix_plugin_contract import bus_target, chain, parameter_target, extra_features

CONTRACT = 'mix_magnitude_human_v3'
FEATURE_COUNT = 184


def fingerprint(descriptor):
    return hashlib.sha256(json.dumps(descriptor, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def control_action(descriptor, scope):
    data = {} if scope.get('scope') == 'master' else {'row': scope['row'], 'force_individual_row': scope.get('force_individual_row', True)}
    master = scope.get('scope') == 'master'
    kind = descriptor['kind']
    if kind in ('gain', 'pan'):
        return {'type': f'set_{"master" if master else "row"}_{kind}', 'data': {**data, 'mode': 'delta', 'delta': 0.0}}
    if kind == 'parameter':
        return {'type': 'adjust_master_effect_param_by_name' if master else 'adjust_effect_param_by_name',
                'data': {**data, 'effect_name_contains': descriptor['effect_name'], 'param_name': descriptor['parameter_name'], 'mode': 'delta', 'delta': 0.0}}
    operation = {'insert': 'ensure', 'remove': 'delete', 'reset': 'hard_reset'}[kind]
    return {'type': f'hard_reset_{"master" if master else "row"}_fx' if operation == 'hard_reset' else f'{operation}_{"master_" if master else ""}effect',
            'data': {**data, **({'effect_name_contains': descriptor['effect_name']} if kind != 'reset' else {})}}


def context_features(project, descriptor, scope):
    from .mix_resolve import MixResolveService
    action = control_action(descriptor, scope)
    # No questionnaire goals, proposal values, or human final values in inputs.
    rows = project.get('rows', [])
    bus = bus_target(project, action)
    if scope.get('scope') == 'master':
        selected = [r for r in rows if r.get('hasAudio')]
        gain, pan = project.get('master_gain_0to3', 2), project.get('master_pan_0to1', .5)
    elif bus is not None:
        selected = [r for r in rows if r.get('group_id') == bus.get('group_id')]
        gain, pan = bus.get('gain', 2), bus.get('pan', .5)
    else:
        selected = [r for r in rows if r.get('row') == scope.get('row')]
        mix = selected[0].get('mix', {}) if selected else {}
        gain, pan = mix.get('gain_0to3', 2), mix.get('pan_0to1', .5)
    def mean(section, key, default=0):
        values = [r.get(section, {}).get(key) for r in selected]
        values = [v for v in values if isinstance(v, (float, int)) and not isinstance(v, bool) and math.isfinite(v)]
        return sum(values) / len(values) if values else default
    def clip(value): return max(-1.0, min(1.0, value))
    stats = [('integrated_lufs_est', 60), ('centroid_hz', 8000), ('hf_rms', 1),
             ('st_rms_mean', 1), ('transient_density', 1), ('phase_corr', 1),
             ('side_ratio', 2), ('low', 1), ('lowmid', 1), ('mid', 1), ('high', 1), ('sibilance', 1)]
    targeted = [clip(gain / 3), clip(pan), clip(mean('features', 'approx_rms')),
                clip(mean('features', 'approx_crest') / 16),
                *[clip(mean('role_probs', role)) for role in ('vocals', 'drums', 'bass', 'guitar', 'synth', 'other')],
                *[clip(mean('audio_stats', key) / scale) for key, scale in stats],
                float(bus is not None), float(scope.get('scope') == 'master'),
                sum(any(key in r.get('audio_stats', {}) for r in selected) for key, _ in stats) / len(stats)]
    return [*MixResolveService().build_training_feature_vector(project=project, goal={}, action=action, strict=True, candidate_actions=[action]),
            *extra_features(project, action), *targeted]


def parameter_descriptor(effect, parameter, *, inserted=False):
    choices = parameter.get('choices')
    if not isinstance(choices, list):
        choices = [parameter[k] for k in sorted((k for k in parameter if k.startswith('choice_') and k[7:].isdigit()), key=lambda k: int(k[7:]))]
    return {'kind': 'parameter', 'effect_id': model_plugin_id(effect), 'effect_name': effect['name'],
            'parameter_id': parameter['id'], 'parameter_name': parameter['name'],
            'type': parameter['type'], 'min': parameter.get('min'), 'max': parameter.get('max'),
            'choices': choices, 'inserted': inserted}


def encode_target(descriptor, value):
    kind = descriptor.get('type', 'float')
    if kind not in ('float', 'bool', 'choice'): return None
    if kind == 'bool':
        return float(value) if isinstance(value, bool) else None
    if kind == 'choice':
        choices = descriptor['choices']
        return float(choices.index(value)) if value in choices else None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    low, high = descriptor.get('min'), descriptor.get('max')
    if not isinstance(low, (int, float)) or not isinstance(high, (int, float)) or not high > low or not low <= value <= high:
        return None
    return (value - low) / (high - low)


def decode_target(descriptor, value):
    if descriptor.get('type') == 'bool': return bool(value >= .5)
    if descriptor.get('type') == 'choice': return descriptor['choices'][int(value)]
    result = descriptor['min'] + max(0.0, min(1.0, value)) * (descriptor['max'] - descriptor['min'])
    # Captured float controls can contain finer values than the UI interval.
    # Preserve those values; only categorical controls require quantization.
    return max(descriptor['min'], min(descriptor['max'], result))


def starting_value(project, descriptor, scope):
    if descriptor.get('inserted'): return None
    action = control_action(descriptor, scope)
    if descriptor['kind'] == 'parameter':
        match = parameter_target(project, action)
        return match[1].get('value') if match else None
    kind = descriptor['kind']
    if scope.get('scope') == 'master':
        return project.get('master_gain_0to3' if kind == 'gain' else 'master_pan_0to1')
    bus = bus_target(project, action)
    if bus is not None: return bus.get(kind)
    row = next((r for r in project.get('rows', []) if r.get('row') == scope.get('row')), {})
    return row.get('mix', {}).get('gain_0to3' if kind == 'gain' else 'pan_0to1')


def features(project, descriptor, scope, direction):
    # Identity is deterministic and independent of the final parameter value.
    digest = bytes.fromhex(fingerprint(descriptor))
    return [*context_features(project, descriptor, scope), float(direction),
            float(descriptor.get('inserted', False)), *[b / 255 for b in digest[:16]]]


def runtime_target(project, action, actions, index, controls):
    """Resolve a unique continuous control using the same coordinates as training."""
    from .mix_plugin_contract import PARAM_ACTIONS, parameter_recreated, proposed_value
    data = action['data']; kind = action['type']
    scope = {'scope': 'master'} if 'master' in kind else {'scope': 'row', 'row': data.get('row'), 'force_individual_row': data.get('force_individual_row', False)}
    if kind in ('set_row_gain', 'set_master_gain', 'set_row_pan', 'set_master_pan'):
        d = {'kind': 'gain' if kind.endswith('gain') else 'pan', 'type': 'float', 'min': 0.0, 'max': 3.0 if kind.endswith('gain') else 1.0}
        start = starting_value(project, d, scope)
        proposal = data.get('value') if data.get('mode') == 'set' else (start + data.get('delta', data.get('value', 0)) if start is not None else None)
    elif kind in PARAM_ACTIONS:
        if parameter_recreated(actions, index): return None
        match = parameter_target(project, action)
        if match:
            effect, parameter = match
            if effect.get('isBypassed') or parameter.get('type') != 'float': return None
            d = supported_descriptor(parameter_descriptor(effect, parameter), effect, controls)
            start = parameter.get('value'); proposal = proposed_value(parameter, data)
        else:
            ensure = 'ensure_master_effect' if scope['scope'] == 'master' else 'ensure_effect'
            if not any(a['type'] == ensure and all(a['data'].get(k) == data.get(k) for k in ('row', 'force_individual_row', 'effect_name_contains')) for a in actions[:index]): return None
            # A newly inserted plugin has no initial snapshot. Only exact known
            # plugin/parameter contracts can supply bounds, never fuzzy guesses.
            found = [d for d in controls.values() if d['kind'] == 'parameter' and d.get('inserted') and d['type'] == 'float'
                     and d['effect_name'].lower() == str(data.get('effect_name_contains', '')).lower()
                     and d['parameter_name'].lower() == str(data.get('param_name', '')).lower()]
            if len(found) != 1 or data.get('mode') != 'set': return None
            d = found[0]; start = None
            proposal = data.get('value')
            if proposal is None and isinstance(data.get('value_norm'), (int, float)):
                proposal = decode_target(d, data['value_norm'])
    else: return None
    if fingerprint(d) not in controls or encode_target(d, proposal) is None: return None
    if start is not None and encode_target(d, start) is None: return None
    direction = 0 if start is None else (1 if proposal > start else -1 if proposal < start else 0)
    if start is not None and direction == 0: return None
    return d, scope, start, proposal, direction


def refine_amount(action, target, amount, apply_score):
    """Bounded decoder. Preserve direction, control range, and classifier veto.

    Amount is a fraction of the full control range, not a multiplier. Existing
    controls never exceed 3x the proposed change or a quarter of their range.
    Unknown/unsafe contexts remain unchanged rather than using another model.
    """
    d, scope, start, proposal, direction = target
    width = d['max'] - d['min']
    amount = max(0.0, min(1.0, float(amount)))
    confidence = 1.0 if apply_score >= .5 else .35
    if start is None:
        predicted = decode_target(d, amount)
        value = proposal + max(-.1 * width, min(.1 * width, predicted - proposal)) * confidence
    else:
        distance = min(amount * width * confidence, 3 * abs(proposal - start), .25 * width)
        value = start + direction * distance
    value = max(d['min'], min(d['max'], value))
    result = copy.deepcopy(action)
    for key in ('delta', 'delta_norm', 'value', 'value_norm', 'refinement_scale', 'clamp_0_1'):
        result['data'].pop(key, None)
    result['data'].update(mode='set', value=value)
    return result
