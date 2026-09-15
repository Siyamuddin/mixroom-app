"""Contextual action selection for the first ONNX model, without future labels."""
import math
from .mix_magnitude_contract import features as amount_features, control_action, fingerprint, parameter_descriptor, encode_target, runtime_target as amount_target
from .mix_plugin_contract import PARAM_ACTIONS, STRUCTURAL_ACTIONS, effect_target, bus_target, parameter_target, proposed_value, parameter_recreated
from .plugin_identity import model_plugin_id, supported_descriptor, verified_unloaded_control

CONTRACT = 'mix_selection_human_v1'
FEATURE_COUNT = 208


def structural_descriptor(kind, effect=None):
    return {'kind': kind, 'type': 'bool', **({'effect_id': model_plugin_id(effect), 'effect_name': effect['name']} if kind != 'reset' else {})}


def choice_coordinate(descriptor, value):
    if descriptor.get('type') == 'float' or descriptor['kind'] != 'parameter': return -1.0
    encoded = encode_target(descriptor, value)
    if encoded is None: return None
    return encoded / max(1, len(descriptor.get('choices', [])) - 1) if descriptor['type'] == 'choice' else encoded


def features(project, descriptor, scope, direction, choice, goal):
    from .mix_resolve import MixResolveService
    action = control_action(descriptor, scope)
    goal_context = MixResolveService().build_training_feature_vector(project=project, goal=goal, action=action, strict=True, candidate_actions=[action])[:23]
    return [*amount_features(project, descriptor, scope, direction), float(choice), *goal_context]


def categorical_value(descriptor, data, current=None):
    value = data.get('value_norm', data.get('value')) if data.get('mode', 'delta') == 'set' else data.get('delta_norm', data.get('delta'))
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value): return None
    if data.get('mode', 'delta') != 'set':
        start = choice_coordinate(descriptor, current)
        if start is None: return None
        value += start
    value = max(0.0, min(1.0, value))
    if descriptor['type'] == 'bool': return value >= .5
    choices = descriptor.get('choices', [])
    return choices[int(math.floor(value * (len(choices)-1) + .5))] if choices else None


def runtime_target(project, action, actions, index, controls):
    kind = action['type']; data = action['data']
    scope = {'scope': 'master'} if 'master' in kind else {'scope': 'row', 'row': data.get('row'), 'force_individual_row': data.get('force_individual_row', False)}
    if kind in ('set_row_gain', 'set_master_gain', 'set_row_pan', 'set_master_pan'):
        target = amount_target(project, action, actions, index, controls)
        if target is None: return None
        d, scope, start, value, direction = target
        return d, scope, direction, -1.0
    if kind in PARAM_ACTIONS:
        if parameter_recreated(actions, index): return None
        match = parameter_target(project, action)
        if match:
            effect, parameter = match
            if effect.get('isBypassed'): return None
            d = supported_descriptor(parameter_descriptor(effect, parameter), effect, controls)
            start = parameter.get('value')
            value = proposed_value(parameter, data) if d['type'] == 'float' else categorical_value(d, data, start)
            if encode_target(d, value) is None: return None
            direction = (1 if value > start else -1 if value < start else 0) if d['type'] == 'float' else 0
            if d['type'] == 'float' and direction == 0: return None
        else:
            target = amount_target(project, action, actions, index, controls)
            if target is not None:
                d, scope, start, value, direction = target
            else:
                ensure = 'ensure_master_effect' if scope['scope'] == 'master' else 'ensure_effect'
                if not any(a['type'] == ensure and insertion_dependency(a, project) == insertion_dependency(action, project) for a in actions[:index]): return None
                found = [d for d in controls.values() if verified_unloaded_control(d) and d['kind']=='parameter' and d.get('inserted') and d['type'] in ('bool','choice')
                         and d['effect_name'].lower()==str(data.get('effect_name_contains','')).lower()
                         and d['parameter_name'].lower()==str(data.get('param_name','')).lower()]
                if len(found)!=1 or data.get('mode')!='set': return None
                d=found[0]; direction=0; value=categorical_value(d,data)
        choice = choice_coordinate(d, value)
        return (d, scope, direction, choice) if fingerprint(d) in controls and choice is not None else None
    if kind not in STRUCTURAL_ACTIONS: return None
    operation = 'insert' if kind.startswith('ensure') else 'remove' if kind.startswith('delete') else 'reset'
    effect = effect_target(project, action)
    if operation == 'insert':
        if effect is not None: return None  # An already-present plugin is not a new choice.
        token = str(data.get('effect_name_contains', '')).lower()
        matches = [d for d in controls.values() if verified_unloaded_control(d) and d['kind'] == 'insert' and d['effect_name'].lower() == token]
        if len(matches) != 1: return None
        d = matches[0]
    elif operation == 'remove':
        if effect is None or not effect.get('effectId'): return None
        d = supported_descriptor(structural_descriptor(operation, effect), effect, controls)
    else: d = structural_descriptor(operation)
    return (d, scope, 0, -1.0) if fingerprint(d) in controls else None


def execution_scope(project, action):
    data = action['data']
    if 'master' in action['type']: return ('master',)
    bus = bus_target(project, action) if project is not None else None
    if bus is not None: return ('bus', bus.get('group_id'))
    return ('row', data.get('row'), data.get('force_individual_row', False))


def insertion_dependency(action, project=None):
    return (*execution_scope(project, action), str(action['data'].get('effect_name_contains', '')).lower())
