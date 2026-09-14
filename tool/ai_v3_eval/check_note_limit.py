"""Offline reproduction of backend/client aggregate generated-note agreement.

Synthetic boundary cases only. No model calls, saved plans or project mutation.
This diagnoses current behavior; it deliberately does not change validation.
"""
import argparse
import json
from pathlib import Path
import subprocess

from compare_request_weight import prepare, contract, _canonical_json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    request, _, _ = prepare()
    cases = []
    for count in (256, 257, 264):
        commands = []
        for i, clip in enumerate(request['core_context']['clips']):
            number = count // 5 + (i < count % 5)
            commands.append({'command_id': f'replace-{i}', 'type': 'midi.replace_notes',
                'arguments': {'clip_id': clip['clip_id'], 'notes': [
                    {'pitch': [60, 38, 40, 52, 52][i], 'start_beat': n * 0.5,
                     'length_beats': 0.5, 'velocity': 0.8} for n in range(number)]}})
        plan = {'schema_version': contract.PLAN_SCHEMA_VERSION, 'outcome': 'plan',
            'user_message': 'Updated the five existing parts.',
            'commands': commands, 'question_options': []}
        payload = {'status': 'completed', 'output': [{'type': 'function_call',
            'name': 'submit_plan_v3', 'arguments': _canonical_json(plan)}]}
        result = {'note_count': count}
        try:
            contract.parse_and_validate_provider_plan(payload,
                command_types=request['supported_command_types'], resource_refs_enabled=True,
                capability_surface=request['capability_surface'], original_request=request['original_request'])
            result['backend_valid'] = True
        except contract.V3ContractError as error:
            result.update(backend_valid=False, backend_error=error.code)
        completed = subprocess.run([args.dart, str(Path(__file__).with_name('check_plan_client.dart'))],
            input=_canonical_json(plan) + '\n', text=True, capture_output=True, timeout=20, check=True)
        result['client'] = json.loads(completed.stdout)
        cases.append(result)
    print(json.dumps({'live_calls': 0, 'cases': cases}, sort_keys=True))

if __name__ == '__main__': main()
