"""Opt-in bounded comparison; identical synthetic state, no runtime adoption.

Candidate extracts only exactly identical enum schemas into local $defs.
Reports contain metadata only; generated plans stay in memory and are piped to
the real Dart contract parser. No app execution, repair, retries or production API.
"""
from __future__ import annotations

import argparse
import copy
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend/llm_proxy/src'))
from common import v3_server_contract as contract
from common.llm_contract import build_openai_responses_request
from common.llm_provider import get_provider
from profile_v3_requests import _request, _canonical_json, _json_bytes
from measure_v3_live_provider import _load_configured_api_key, _usage

PROMPT = 'replace all the notes in the instruments. should be same instruments but happy and energetic notes. should be like bangladesh'

def digest(value):
    return hashlib.sha256(_canonical_json(value).encode()).hexdigest()

def expand(schema):
    defs = schema.get('$defs', {})
    def visit(value):
        if isinstance(value, dict):
            if '$ref' in value:
                assert len(value) == 1 and value['$ref'].startswith('#/$defs/')
                return visit(defs[value['$ref'].split('/')[-1]])
            return {k: visit(v) for k, v in value.items() if k != '$defs'}
        if isinstance(value, list):
            return [visit(v) for v in value]
        return value
    return visit(schema)

def deduplicate(schema):
    assert '$defs' not in schema
    counts = Counter()
    def collect(value):
        if isinstance(value, dict):
            assert '$ref' not in value
            if isinstance(value.get('enum'), list):
                counts[_canonical_json(value)] += 1
            for child in value.values(): collect(child)
        elif isinstance(value, list):
            for child in value: collect(child)
    collect(schema)
    selected = sorted(key for key, count in counts.items() if count > 1 and len(key.encode()) > 120)
    keys = {value: f'e{index}' for index, value in enumerate(selected)}
    def visit(value):
        if isinstance(value, dict):
            encoded = _canonical_json(value)
            if encoded in keys: return {'$ref': f'#/$defs/{keys[encoded]}'}
            return {k: visit(v) for k, v in value.items()}
        if isinstance(value, list): return [visit(v) for v in value]
        return value
    result = visit(schema)
    if keys: result['$defs'] = {keys[k]: json.loads(k) for k in selected}
    assert expand(result) == schema
    assert _json_bytes(result) <= _json_bytes(schema)
    return result

def fixture():
    body = _request(row_count=5, clip_count=5, turn_count=0,
        full_command_surface=True, library_asset_count=135, include_library_asset_metadata=True)
    body['original_request'] = PROMPT
    body['conversation'] = [
        {'role': role, 'content': content}
        for role, content in [
            ('user', 'Create an eight-bar piano, drums and bass arrangement.'),
            ('assistant', 'The piano, drums and bass are arranged in eight bars.'),
            ('user', 'Add two contrasting eight-bar electric-guitar sections.'),
            ('assistant', 'Two electric-guitar sections are in place.'),
            ('user', 'Keep the instruments and section positions.'),
            ('assistant', 'The instruments and section positions are unchanged.'),
            ('user', 'Keep the mix clean and balanced.'),
            ('assistant', 'The existing arrangement is ready for note editing.'),
        ]]
    ctx = body['core_context']
    ctx['project'].update(beats_per_bar=4, midi_boundary_policy='extend_1ms_v1')
    ctx['groups'] = []
    instruments = [
        ('synthetic-piano', 'Piano', 21, 108),
        ('synthetic-drums', 'Drums', 35, 81),
        ('synthetic-bass', 'Bass', 24, 84),
        ('sfz.guitar.clean_electric', 'Electric Guitar', 40, 86),
    ]
    ctx['instruments'] = [i[0] for i in instruments]
    ctx['instrument_catalog'] = [{'instrument_id': i, 'name': n,
        'playable_pitch_ranges': [{'low': low, 'high': high}]} for i, n, low, high in instruments]
    # Five editable parts on four instrument rows plus one empty row, like the
    # observed shape. This is not a copy of project #132 or its unretained plan.
    for index, row in enumerate(ctx['rows']):
        row.update(lane_kind='instrument' if index < 4 else 'audio',
            instrument_id=instruments[min(index, 3)][0] if index < 4 else '',
            name=instruments[min(index, 3)][1] if index < 4 else 'Empty', effects=[])
        row['has_usable_signal'] = index < 4
    for index, clip in enumerate(ctx['clips']):
        row = min(index, 3)
        pitch = [60, 38, 40, 52][row]
        clip.update(row_id=row + 1, kind='midi', instrument_id=instruments[row][0],
            start_beat=32 if index == 4 else 0, length_beats=32,
            midi_notes=[{'pitch': pitch + (n % 3 if row != 1 else 0),
                'start_beat': n * 0.5, 'length_beats': 0.5, 'velocity': 0.75}
                for n in range(64)])
    return body

def prepare():
    body = fixture()
    request = contract.validate_context_request(body, raw_body_bytes=_json_bytes(body))
    baseline = contract.build_provider_request(request, model='gpt-5.6-luna',
        reasoning_effort='low', max_output_tokens=8192, prompt_cache_retention='24h', store=True)
    candidate = copy.deepcopy(baseline)
    schema = baseline['tools'][0]['parameters']
    candidate['tools'][0]['parameters'] = deduplicate(schema)
    restored = copy.deepcopy(candidate)
    restored['tools'][0]['parameters'] = expand(candidate['tools'][0]['parameters'])
    assert restored == baseline
    return request, baseline, candidate

def measure_body(body):
    upstream = build_openai_responses_request(body)
    return {'request_bytes': _json_bytes(body), 'upstream_bytes': _json_bytes(upstream),
        'wire_bytes': len(json.dumps(upstream).encode()),
        'schema_bytes': _json_bytes(body['tools'][0]['parameters']),
        'request_sha256': digest(body), 'upstream_sha256': digest(upstream),
        'definitions': len(body['tools'][0]['parameters'].get('$defs', {}))}

def scope_check(plan, request):
    originals = {c['clip_id']: c for c in request['core_context']['clips']}
    replaced = set()
    for command in plan['commands']:
        if command['type'] != 'midi.replace_notes': return False
        args = command['arguments']
        ref = args.get('clip_ref') or {}
        clip_id = args.get('clip_id') or ref.get('clip_id')
        if clip_id not in originals or clip_id in replaced or not args['notes']: return False
        if args['notes'] == originals[clip_id]['midi_notes']: return False
        replaced.add(clip_id)
    return replaced == set(originals)

def run_trial(request, body, key, checker):
    result = {}
    started = time.perf_counter()
    try:
        response = get_provider('openai').forward_request(api_key=key,
            request_body=body, timeout_seconds=55)
        result['provider_ms'] = round((time.perf_counter() - started) * 1000)
        result['http_status'] = response['statusCode']
        if response['statusCode'] != 200:
            result['error'] = 'upstream_error'
            return result
        payload = json.loads(response['body'])
        result.update(_usage(payload))
        t = time.perf_counter()
        plan = contract.parse_and_validate_provider_plan(payload,
            command_types=request['supported_command_types'], resource_refs_enabled=True,
            capability_surface=request['capability_surface'], original_request=request['original_request'])
        result['backend_validation_ms'] = round((time.perf_counter() - t) * 1000, 3)
        result['backend_valid'] = True
        checker.stdin.write(_canonical_json(plan) + '\n'); checker.stdin.flush()
        client = json.loads(checker.stdout.readline())
        result['client_valid'] = client['valid']
        if not client['valid']: result['client_error'] = client['error']
        result['scope_ok'] = scope_check(plan, request)
        result['command_count'] = len(plan['commands'])
        result['note_count'] = sum(len(c['arguments'].get('notes', [])) for c in plan['commands'])
        result['executable_contract_success'] = client['valid'] and result['scope_ok']
    except contract.V3ContractError as error:
        result['error'] = error.code
    except (TimeoutError, OSError) as error:
        result['error'] = 'timeout' if isinstance(error, TimeoutError) else 'transport_error'
    finally:
        result['elapsed_ms'] = round((time.perf_counter() - started) * 1000)
    return result

def summarize(results):
    report = {}
    for variant in ('baseline', 'candidate'):
        rows = [r for r in results if r['variant'] == variant]
        complete = [r['provider_ms'] for r in rows if 'provider_ms' in r and r.get('http_status') == 200]
        report[variant] = {'trials': len(rows),
            'timeouts': sum(r.get('error') == 'timeout' for r in rows),
            'contract_successes': sum(bool(r.get('executable_contract_success')) for r in rows),
            'client_rejections': sum(r.get('client_valid') is False for r in rows),
            'completed_provider_median_ms': statistics.median(complete) if complete else None,
            'completed_provider_max_ms': max(complete) if complete else None}
    return report

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute-live', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or ROOT in output.parents: parser.error('Reports must be outside the repository')
    request, baseline, candidate = prepare()
    report = {'schema_equivalence': True, 'synthetic_fixture_sha256': digest(fixture()),
        'timeout_seconds': 55, 'repair_enabled': False, 'streaming': False,
        'baseline': measure_body(baseline), 'candidate': measure_body(candidate), 'results': []}
    print(json.dumps(report), flush=True)
    if not args.execute_live: return
    os.environ.setdefault('SSL_CERT_FILE', '/etc/ssl/cert.pem')
    key = _load_configured_api_key()
    if not key: raise SystemExit('Provider key unavailable')
    checker = subprocess.Popen([args.dart, str(Path(__file__).with_name('check_plan_client.dart'))],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=ROOT)
    try:
        # No warmup requests: first pair is labelled separately; later cache
        # values are reported, not assumed comparable. Exactly twelve calls.
        for repeat in range(6):
            for variant in (('baseline', 'candidate') if repeat % 2 == 0 else ('candidate', 'baseline')):
                result = run_trial(request, baseline if variant == 'baseline' else candidate, key, checker)
                result.update(variant=variant, repeat=repeat, first_pair=repeat == 0)
                report['results'].append(result)
                report['summary'] = summarize(report['results'])
                output.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
                print(json.dumps(result, sort_keys=True), flush=True)
    finally:
        checker.stdin.close()
        checker.wait(timeout=10)

if __name__ == '__main__': main()
