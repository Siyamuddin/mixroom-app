"""Evaluation-only adjacent pitch summary; no runtime imports or adoption.

Fixed 20/20 interleaved first-pass calls. Outputs are synthetic, outside repo.
Same model/deadline/schema/instructions; only one extra input-text block differs.
"""
import argparse
import copy
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import evaluate_pitch as original


def add_summary(body, surface):
    result = copy.deepcopy(body)
    summary = {
        'inclusive_pitch_intervals_by_instrument': {
            item.instrument_id: [[interval.low, interval.high]
                                for interval in item.playable_pitch_ranges]
            for item in surface.instruments},
        'current_instrument_by_row': {str(row.row_id): row.instrument_id
                                      for row in surface.rows},
    }
    content = result['messages'][0]['content']
    assert content[-1]['text'].startswith('ORIGINAL_REQUEST_VERBATIM:\n')
    content.insert(-1, {'type': 'input_text', 'text':
        'MIDI_PITCH_CAPABILITIES_JSON (resolve each command\'s effective instrument after earlier commands; '
        'intervals are inclusive, gaps are unavailable, an empty interval list means unrestricted):\n'
        + json.dumps(summary, sort_keys=True, separators=(',', ':'))})
    return result


def prepare(index):
    old, _, _ = original.prepare(index)
    body = original.ApiResponsesTests()._v3_midi_repair_body()
    body.update({key: copy.deepcopy(value) for key, value in old.items()
                 if key != 'capability_surface'})
    body['supported_command_types'] = sorted(body['supported_command_types'])
    ctx = body['core_context']
    # Synthetic distractor catalog approximates catalog pressure in the app.
    # None of these identifiers/names is copied from a user project.
    for n in range(135 - len(ctx['instrument_catalog'])):
        identifier = f'synthetic-catalog-{n:03d}'
        ctx['instruments'].append(identifier)
        ctx['instrument_catalog'].append({'instrument_id': identifier,
            'name': f'Synthetic instrument {n}',
            'playable_pitch_ranges': [{'low': 48, 'high': 84}]})
    if original.CASES[index][0] == 'drums':
        ctx['instrument_catalog'][0]['playable_pitch_ranges'] = [
            {'low': low, 'high': high} for low, high in
            [(35, 38), (42, 42), (46, 46), (49, 49), (51, 51)]]
    encoded = json.dumps(body, sort_keys=True, separators=(',', ':')).encode()
    valid = original.contract.validate_context_request(body, raw_body_bytes=len(encoded))
    base = original.contract.build_provider_request(valid, model='gpt-5.6-luna',
        reasoning_effort='low', max_output_tokens=8192)
    return valid, base, add_summary(base, valid['capability_surface'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-live', action='store_true')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if original.ROOT == args.output.resolve() or original.ROOT in args.output.resolve().parents:
        raise SystemExit('Use an output path outside the repository')
    for i in range(5):
        _, base, changed = prepare(i)
        print(json.dumps({'case': original.CASES[i][0],
            'baseline_bytes': len(json.dumps(base).encode()),
            'candidate_bytes': len(json.dumps(changed).encode())}), flush=True)
    if not args.execute_live:
        return
    os.environ.setdefault('SSL_CERT_FILE', '/etc/ssl/cert.pem')
    key = original._load_configured_api_key()
    if not key:
        raise SystemExit('Missing provider key')
    jobs = [(i, r, v) for r in range(4) for i in range(5)
            for v in (('baseline', 'candidate') if (i+r) % 2 == 0
                      else ('candidate', 'baseline'))]
    results = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda job: original.execute(job, key, prepare), jobs):
            results.append(result)
            args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2))
            print(json.dumps({k: v for k, v in result.items()
                              if k not in {'payload', 'plan'}}), flush=True)


if __name__ == '__main__':
    main()
