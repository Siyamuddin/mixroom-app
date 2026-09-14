"""Exactly 20 previous-candidate / 20 revised-candidate first-pass calls.

Baseline labels mean the PREVIOUS inactive candidate, not runtime instructions.
No credential lookup, repair, automatic adoption, or app/project mutation.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

import evaluate_row_rebuild as original
from row_rebuild_revision import candidate


def prepare(index):
    body, valid, _, previous = original.prepare(index)
    revised = copy.deepcopy(previous)
    revised['instructions'] = candidate(previous['instructions'])
    return body, valid, previous, revised


def manifest():
    requests = []
    for index in range(5):
        body, _, previous, revised = prepare(index)
        requests.append({'case': original.NAMES[index], 'request': body,
            'previous_sha256': hashlib.sha256(original.canonical(previous).encode()).hexdigest(),
            'revised_sha256': hashlib.sha256(original.canonical(revised).encode()).hexdigest()})
    files = ('score_row_rebuild.py', 'row_rebuild_revision.py', 'evaluate_row_rebuild.py',
             'evaluate_row_rebuild_revision.py')
    return {'requests': requests, 'schedule': original.jobs(),
        'variant_labels': {'baseline': 'previous_candidate', 'candidate': 'revised_candidate'},
        'source_sha256': {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                          for name in files},
        'model': original.MODEL, 'provider_deadline_seconds': original.DEADLINE,
        'max_output_tokens': 16384, 'concurrency': 2, 'repair': False,
        'adoption': {'minimum_successes': 18, 'minimum_gain': 2,
                    'no_increase_in': ['last_row', 'capacity', 'pitch', 'other_invalid',
                                       'scope', 'protected_content', 'language']}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-live', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    frozen = output.with_suffix('.manifest.json')
    if original.ROOT == output or original.ROOT in output.parents:
        raise SystemExit('Output must be outside repository')
    if output.exists() or frozen.exists():
        raise SystemExit('Refusing to overwrite evaluation evidence')
    snapshot = manifest()
    print('Five unchanged scenarios and paired request hashes verified.', flush=True)
    if not args.execute_live:
        return
    key = (os.environ.get('LLM_API_KEY') or os.environ.get('OPENAI_API_KEY') or '').strip()
    if not key:
        raise SystemExit('A locally supplied provider key is required')
    os.environ.setdefault('SSL_CERT_FILE', '/etc/ssl/cert.pem')
    with frozen.open('x') as stream:
        stream.write(original.canonical(snapshot) + '\n')
    with output.open('x') as stream, ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda job: original.execute(job, key, prepare_request=prepare), original.jobs()):
            stream.write(original.canonical(result) + '\n')
            stream.flush()
            print(json.dumps({k: v for k, v in result.items()
                if k not in {'context', 'original_request', 'plan', 'validation_reason'}}), flush=True)
    print('40 first-pass calls complete; client, scope and language gates still required.', flush=True)


if __name__ == '__main__':
    main()
