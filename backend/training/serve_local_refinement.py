#!/usr/bin/env python3
"""Loopback-only refinement runner for a debug app; no upload or cloud deployment.

Run from the repository root, then build Flutter with
--dart-define=MIXROOM_LOCAL_REFINE_URL=http://127.0.0.1:8765
Chat continues to use its configured provider. This development server does not
validate app authentication and deliberately binds only to IPv4 loopback.
"""
import argparse
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'llm_proxy' / 'src'))
from common.mix_resolve import MixResolveService, MixResolveValidationError, OnnxMixModelRunner


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--model-directory', type=Path)
    parser.add_argument('--allow-development-model', action='store_true')
    args = parser.parse_args()
    if args.allow_development_model:
        os.environ['MIX_ALLOW_DEVELOPMENT_MODELS'] = 'true'
    if args.model_directory:
        from evaluate_producer_models import CandidateRunner
        runner = CandidateRunner(args.model_directory)
    else:
        runner = OnnxMixModelRunner()
    feature_count = 141 if runner.feature_contract() == 'mix_refine_plugins_v2' else 77
    runner.predict_apply_score([0.0] * feature_count)
    magnitude_count = {'mix_refine_v1': 77, 'mix_refine_plugins_v2': 141, 'mix_magnitude_human_v3': 184}[runner.magnitude_contract()]
    runner.predict_scalar([0.0] * magnitude_count)
    resolver = MixResolveService(runner=runner)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Never log tokens, prompts, or project state.

        def reply(self, status, body):
            raw = json.dumps(body).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            if self.path != '/health':
                return self.reply(404, {'error': 'not_found'})
            self.reply(200, {'status': 'ready', **runner.observability_context()})

        def do_POST(self):
            if self.path != '/v1/mix/resolve':
                return self.reply(404, {'error': 'not_found'})
            if not self.headers.get('Content-Type', '').startswith('application/json'):
                return self.reply(415, {'error': 'application/json required'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 8 * 1024 * 1024:
                    return self.reply(413, {'error': 'invalid request size'})
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise ValueError('Expected an object')
                if not isinstance(body.get('project_state', body.get('project')), dict):
                    raise ValueError('project_state must be an object')
                if not isinstance(body.get('goal'), dict):
                    raise ValueError('goal must be an object')
                if not isinstance(body.get('actions'), list):
                    raise ValueError('actions must be a list')
                requested_contract = body.get('mix_feature_contract_version', body.get('feature_contract_version'))
                if requested_contract and requested_contract != 'mix_refine_v1':
                    raise ValueError('mix_feature_contract_version_mismatch')
                if not isinstance(body.get('strict'), bool):
                    raise ValueError('strict must be boolean')
                started = time.monotonic()
                result = resolver.resolve(
                    project=body.get('project_state', body.get('project')),
                    goal=body.get('goal'), actions=body.get('actions'),
                    strict=body['strict'],
                )
                result['request_duration_ms'] = round((time.monotonic() - started) * 1000)
                print(json.dumps({'event': 'refinement', 'actions': len(result['actions']),
                                  'fallback': result.get('fallback_used'),
                                  'duration_ms': result['request_duration_ms']}), flush=True)
                self.reply(200, result)
            except (ValueError, TypeError, KeyError, MixResolveValidationError) as exc:
                self.reply(400, {'error': str(exc)})

    server = HTTPServer(('127.0.0.1', args.port), Handler)
    print(json.dumps({'url': f'http://127.0.0.1:{args.port}',
                      **runner.observability_context()}), flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
