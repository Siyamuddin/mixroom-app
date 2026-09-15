"""Opt-in synthetic first-pass eval; no projects, production tables, or retries.

Uses the same provider adapter as the local bridge, bypassing handler repair so
first-pass outcomes cannot be confused with recovery. Outputs stay outside repo.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'backend/llm_proxy/src'), str(ROOT / 'backend/llm_proxy/tests')]
from common import v3_server_contract as contract
from common.llm_provider import get_provider
from common.llm_contract import build_openai_responses_request
from test_api_responses import ApiResponsesTests
from measure_v3_live_provider import _load_configured_api_key
from pitch_candidate import candidate
from row_rebuild_revision import historical_instructions

GUITAR = 'sfz.guitar.clean_electric'
CASES = [
    ('followup', 'Create two contrasting 8-bar sections', GUITAR, 40, 86, 2),
    ('low_guitar', 'Create an eight-bar heavy metal guitar riff with rich low chords. Keep the guitar instrument.', GUITAR, 40, 86, 1),
    ('flute', 'Create an eight-bar lively flute melody with a low opening and a bright contrasting ending. Keep the flute instrument.', 'synthetic-flute', 60, 96, 1),
    ('drums', 'Create an eight-bar energetic drum groove with kick, snare, hats and fills. Keep the drum instrument.', 'synthetic-remapped-drums', 35, 81, 1),
    ('switch', 'Change row 101 from drums to Electric Guitar, then create an eight-bar heavy metal chord progression on that row.', GUITAR, 40, 86, 1),
]

def prepare(index):
    name, prompt, instrument, low, high, sections = CASES[index]
    body = ApiResponsesTests()._v3_midi_repair_body()
    body['supported_command_types'] = sorted(contract.SERVER_COMMAND_TYPES)
    body['resource_refs_enabled'] = True
    body['original_request'] = prompt
    ctx = body['core_context']
    ctx['project'].update(bpm=108, beats_per_bar=4)
    ctx['clips'] = []
    ctx['rows'][0]['instrument_id'] = instrument
    ctx['instrument_catalog'] = [{'instrument_id': instrument,
        'name': 'Electric Guitar' if instrument == GUITAR else name,
        'playable_pitch_ranges': [{'low': low, 'high': high}]}]
    ctx['instruments'] = [instrument]
    if name == 'switch':
        ctx['rows'][0]['instrument_id'] = 'synthetic-drums'
        ctx['instruments'].append('synthetic-drums')
        ctx['instrument_catalog'].append({'instrument_id': 'synthetic-drums',
            'name': 'Drums', 'playable_pitch_ranges': [{'low': 35, 'high': 81}]})
    body['conversation'] = []
    if name == 'followup':
        body['conversation'] = [
            {'role': 'user', 'content': 'electric guitar heavy metal 16 bars suoper rich chord prog'},
            {'role': 'assistant', 'content': 'I can create the electric-guitar progressive metal chord part, but generated material is limited to 8 bars at a time—would you like an 8-bar section or two 8-bar sections?'}]
    encoded = json.dumps(body, sort_keys=True, separators=(',', ':')).encode()
    valid = contract.validate_context_request(body, raw_body_bytes=len(encoded))
    base = contract.build_provider_request(valid, model='gpt-5.6-luna',
        reasoning_effort='low', max_output_tokens=8192)
    base['instructions'] = historical_instructions(base['instructions'])
    changed = copy.deepcopy(base)
    changed['instructions'] = candidate(base['instructions'])
    a, b = build_openai_responses_request(base), build_openai_responses_request(changed)
    assert {k:v for k,v in a.items() if k != 'instructions'} == {k:v for k,v in b.items() if k != 'instructions'}
    context_text = next(c['text'] for c in base['messages'][0]['content']
        if c.get('text', '').startswith('CORE_CONTEXT_V3_JSON:\n'))
    assert json.loads(context_text.split('\n', 1)[1])['instrument_catalog'] == ctx['instrument_catalog']
    return valid, base, changed

def execute(job, key, prepare_request=prepare):
    index, repeat, variant = job
    valid, base, changed = prepare_request(index)
    body = base if variant == 'baseline' else changed
    result = {'case': CASES[index][0], 'repeat': repeat, 'variant': variant,
        'request_sha256': hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()}
    started = time.monotonic()
    try:
        response = get_provider('openai').forward_request(api_key=key,
            request_body=body, timeout_seconds=55)
        result['status'] = response['statusCode']
        if result['status'] != 200:
            result['error'] = 'upstream_error'
            return result
        payload = json.loads(response['body'])
        # Synthetic data only; retain generated output for independent review.
        result['payload'] = payload
        plan = contract.parse_and_validate_provider_plan(payload,
            command_types=valid['supported_command_types'], resource_refs_enabled=True,
            capability_surface=valid['capability_surface'], original_request=valid['original_request'])
        result['valid'] = True
        result['plan'] = plan
        commands = plan['commands']
        created = [c for c in commands if c['type'] == 'midi.create_clip']
        wanted = CASES[index][5]
        result['scope_ok'] = (len(created) == wanted and
            all(c['arguments']['length_beats'] == 32 for c in created) and
            (wanted == 1 or sorted(c['arguments']['start_beat'] for c in created) == [0, 32]))
        allowed = {'midi.create_clip', 'row.create'}
        if CASES[index][0] == 'switch': allowed.add('row.set_instrument')
        result['scope_ok'] &= all(c['type'] in allowed for c in commands)
        result['instrument_ok'] = instruments_match(commands, index)
        result['success'] = result['scope_ok'] and result['instrument_ok'] and plan['outcome'] == 'plan'
    except contract.V3ContractError as error:
        result.update(error=error.code, details=error.repair_details)
    except Exception as error:
        result['error'] = type(error).__name__
    finally:
        result['elapsed_ms'] = round((time.monotonic() - started) * 1000)
    return result

def instruments_match(commands, index):
    rows = {101: 'synthetic-drums' if CASES[index][0] == 'switch' else CASES[index][2]}
    for command in commands:
        args = command['arguments']
        if command['type'] == 'row.create':
            rows[command['command_id']] = args['lane'].get('instrument_id')
        elif command['type'] == 'row.set_instrument':
            rows[args.get('row_id', (args.get('row_ref') or {}).get('command_id'))] = args['instrument_id']
        elif command['type'] == 'midi.create_clip':
            target = args['destination']
            key = target.get('row_id', (target.get('row_ref') or {}).get('command_id'))
            if rows.get(key) != CASES[index][2]: return False
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute-live', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if ROOT == args.output.resolve() or ROOT in args.output.resolve().parents:
        raise SystemExit('Use an output path outside the repository')
    for i in range(5): prepare(i)
    print('Offline request checks passed.', flush=True)
    if not args.execute_live: return
    os.environ.setdefault('SSL_CERT_FILE', '/etc/ssl/cert.pem')
    key = _load_configured_api_key()
    if not key: raise SystemExit('Missing provider key')
    jobs = [(i, r, v) for r in range(4) for i in range(5)
            for v in (('baseline', 'candidate') if (i+r)%2 == 0 else ('candidate', 'baseline'))]
    results = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda job: execute(job, key), jobs):
            results.append(result)
            args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2))
            print(json.dumps({k:v for k,v in result.items() if k not in {'payload','plan'}}), flush=True)

if __name__ == '__main__': main()
