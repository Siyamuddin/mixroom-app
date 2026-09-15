"""Two explicit repair probes against a captured synthetic baseline failure."""
import argparse
import json
import os
import time
from pathlib import Path
from evaluate_pitch import prepare, get_provider, _load_configured_api_key, contract, CASES, ROOT
from handlers.api_responses import _v3_semantic_repair_request_body

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute-live', action='store_true')
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if ROOT == args.output.resolve() or ROOT in args.output.resolve().parents:
        raise SystemExit('Use an output path outside the repository')
    source = next(r for r in json.loads(args.input.read_text())
        if r['variant'] == 'baseline' and r.get('error') == 'v3_plan_midi_pitch_unavailable')
    index = next(i for i,c in enumerate(CASES) if c[0] == source['case'])
    valid, body, _ = prepare(index)
    try:
        contract.parse_and_validate_provider_plan(source['payload'],
            command_types=valid['supported_command_types'], resource_refs_enabled=True,
            capability_surface=valid['capability_surface'], original_request=valid['original_request'])
    except contract.V3ContractError as error:
        details = error.repair_details
        assert details and error.code == 'v3_plan_midi_pitch_unavailable'
    repair = _v3_semantic_repair_request_body(body, 'v3_plan_midi_pitch_unavailable', details)
    remaining = max(0, int(55 - source['elapsed_ms'] / 1000))
    print(json.dumps({'details': details, 'repair_budget_seconds': remaining}), flush=True)
    if not args.execute_live or remaining <= 0: return
    os.environ.setdefault('SSL_CERT_FILE', '/etc/ssl/cert.pem')
    key = _load_configured_api_key()
    results = []
    for repeat in range(2):
        result = {'repeat': repeat, 'timeout_seconds': remaining}
        start = time.monotonic()
        try:
            response = get_provider('openai').forward_request(api_key=key, request_body=repair, timeout_seconds=remaining)
            result['status'] = response['statusCode']
            payload = json.loads(response['body'])
            result['payload'] = payload
            result['plan'] = contract.parse_and_validate_provider_plan(payload,
                command_types=valid['supported_command_types'], resource_refs_enabled=True,
                capability_surface=valid['capability_surface'], original_request=valid['original_request'])
            result['valid'] = True
        except Exception as error:
            result['error'] = getattr(error, 'code', type(error).__name__)
        result['elapsed_ms'] = round((time.monotonic()-start)*1000)
        results.append(result)
        args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2))
        print(json.dumps({k:v for k,v in result.items() if k not in {'payload','plan'}}), flush=True)

if __name__ == '__main__': main()
