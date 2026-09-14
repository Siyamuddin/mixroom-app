"""Opt-in 20/20 first-pass comparison. No handler repair or production access.

Synthetic outputs are retained outside the repository for client preparation
and independent scope/language review. No automatic instruction adoption.
Only locally supplied environment credentials are accepted; never fetch SSM.
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
sys.path.insert(0, str(ROOT / 'backend/llm_proxy/src'))
from common import v3_server_contract as contract
from common.llm_contract import build_openai_responses_request
from common.llm_provider import get_provider
from row_rebuild_candidate import candidate
from row_rebuild_revision import historical_instructions

FIXTURE = ROOT / 'backend/llm_proxy/tests/fixtures/row_rebuild_v1.json'
MODEL = 'gpt-5.6-luna'
DEADLINE = 105
NAMES = ('jazz_restart', 'spare_capacity', 'full_capacity', 'single_row', 'partial_rebuild')


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def prepare(index):
    fixture = json.loads(FIXTURE.read_text())
    context = copy.deepcopy(fixture['cases'][0]['context'])
    project = context['project']
    project.update(generated_midi_policy='notes_512_v1', midi_boundary_policy='extend_1ms_v1')
    count, maximum = ((6, 8), (6, 8), (6, 6), (1, 2), (6, 6))[index]
    context['rows'] = context['rows'][:count]
    context['clips'] = context['clips'][:count]
    project['row_capacity'] = dict(current_rows=count, max_rows=maximum, can_create=count < maximum)
    prompts = (
        fixture['original_request'],
        'Remove all existing rows and their clips. Build a new instrumental arrangement from scratch, with new rows and new MIDI parts. Choose the musical style yourself.',
        'Remove all existing rows and their clips. Build a new instrumental arrangement from scratch, with new rows and new MIDI parts. Choose the musical style yourself.',
        'Remove the existing row and its clip. Create a new instrument row with a fresh eight-bar melody. Do not reuse the old row.',
        'Replace rows 100 through 104 and their clips with new instrument rows and new MIDI parts. Preserve row 105 and its clip exactly as they are. Choose the musical style yourself.',
    )
    history = []
    if index == 0:
        history = [
            {'role': 'user', 'content': 'Make an energetic rock arrangement with a big ending.'},
            {'role': 'assistant', 'content': 'Created six energetic rock parts with a strong final section.'},
        ]
        # Explicitly synthetic starting rock parts, not a recovered user project.
        context['instruments'].append('sfz.guitar.clean_electric')
        context['instrument_catalog'].append({
            'instrument_id': 'sfz.guitar.clean_electric', 'name': 'Electric Guitar',
            'playable_pitch_ranges': [{'low': 40, 'high': 86}],
        })
        for row in context['rows']:
            row['instrument_id'] = 'sfz.guitar.clean_electric'
        for clip in context['clips']:
            clip['instrument_id'] = 'sfz.guitar.clean_electric'
    body = dict(request_contract='mixroom_v3_context_v2',
                plan_schema_version='plan_v3_prototype_2',
                original_request=prompts[index], conversation=history,
                core_context=context, resource_refs_enabled=True,
                supported_command_types=sorted(contract.SERVER_COMMAND_TYPES))
    valid = contract.validate_context_request(body, raw_body_bytes=len(canonical(body).encode()))
    baseline = contract.build_provider_request(valid, model=MODEL,
        reasoning_effort='low', max_output_tokens=16384)
    baseline['instructions'] = historical_instructions(baseline['instructions'])
    changed = copy.deepcopy(baseline)
    changed['instructions'] = candidate(baseline['instructions'])
    upstream = [build_openai_responses_request(item) for item in (baseline, changed)]
    assert {k: v for k, v in upstream[0].items() if k != 'instructions'} == {
        k: v for k, v in upstream[1].items() if k != 'instructions'}
    return body, valid, baseline, changed


def jobs():
    return [(i, repeat, variant) for repeat in range(4) for i in range(5)
            for variant in (('baseline', 'candidate') if (i + repeat) % 2 == 0
                            else ('candidate', 'baseline'))]


def assess(payload, valid):
    """Use the real structure and ordered semantics, never a substitute validator.

    Keep structurally valid rejected plans for diagnostic/client cross-checks.
    Executability alone is NOT a scope, language or adoption success.
    """
    result = {'backend_valid': False, 'review_required': True}
    try:
        plan = contract.parse_provider_plan_structure(payload,
            command_types=valid['supported_command_types'], resource_refs_enabled=True,
            capability_surface=valid['capability_surface'],
            original_request=valid['original_request'])
        result['plan'] = plan
        result['outcome'] = plan['outcome']
        contract.validate_plan_capabilities(plan, valid['capability_surface'])
        result['backend_valid'] = True
    except contract.V3ContractError as error:
        result['error'] = error.code
        # Server-owned validation reason; no raw provider envelope is logged.
        result['validation_reason'] = str(error)
    return result


def execute(job, key, provider=None, prepare_request=prepare):
    index, repeat, variant = job
    body, valid, baseline, changed = prepare_request(index)
    request = baseline if variant == 'baseline' else changed
    result = dict(case=NAMES[index], repeat=repeat, variant=variant,
                  provider_attempts=1, context=body['core_context'],
                  original_request=body['original_request'],
                  request_sha256=hashlib.sha256(canonical(request).encode()).hexdigest())
    started = time.monotonic()
    try:
        response = (provider or get_provider('openai')).forward_request(
            api_key=key, request_body=request, timeout_seconds=DEADLINE)
        result['status'] = response['statusCode']
        if result['status'] == 200:
            result.update(assess(json.loads(response['body']), valid))
        else:
            result['error'] = 'upstream_error'
    except Exception as error:
        result['error'] = type(error).__name__
    finally:
        result['elapsed_ms'] = round((time.monotonic() - started) * 1000)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-live', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if ROOT == output or ROOT in output.parents:
        raise SystemExit('Output must be outside the repository')
    if output.exists():
        raise SystemExit('Refusing to overwrite existing evaluation evidence')
    for index in range(5):
        _, _, baseline, changed = prepare(index)
        print(json.dumps(dict(case=NAMES[index], baseline_bytes=len(canonical(baseline).encode()),
                              candidate_bytes=len(canonical(changed).encode()))), flush=True)
    if not args.execute_live:
        return
    key = (os.environ.get('LLM_API_KEY') or os.environ.get('OPENAI_API_KEY') or '').strip()
    if not key:
        raise SystemExit('Set a local LLM_API_KEY or OPENAI_API_KEY; no cloud credential lookup is performed.')
    os.environ.setdefault('SSL_CERT_FILE', '/etc/ssl/cert.pem')
    # Exclusive creation prevents accidental duplicate runs/overwriting evidence.
    with output.open('x') as stream, ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda job: execute(job, key), jobs()):
            stream.write(canonical(result) + '\n')
            stream.flush()
            print(json.dumps({k: v for k, v in result.items()
                              if k not in {'context', 'original_request', 'plan', 'validation_reason'}}), flush=True)
    print('40 first-pass calls complete. Scope, client and language checks are still required; no adoption.', flush=True)


if __name__ == '__main__':
    main()
