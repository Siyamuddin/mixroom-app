"""Fake-clock regression gates for the real long-path deadline and settlement."""
import json
from contextlib import redirect_stdout
from io import StringIO
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import test_api_responses as helpers
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tool/ai_v3_eval'))
import local_v3_bridge as bridge


class TimeoutReadinessTests(unittest.TestCase):
    def test_long_runtime_caps_at_105_even_with_larger_environment(self):
        with patch.dict(os.environ, {'AI_V3_TIMEOUT_SECONDS': '999',
                'AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS': '999'}):
            self.assertEqual(bridge.api_responses._v3_request_timeout_seconds(
                helpers._LambdaContext(115000)), 105)
        self.assertEqual(bridge._LONG_MAX_PROVIDER_TIMEOUT_SECONDS, 105)

    def test_long_shared_deadline_and_settlement(self):
        for durations, repair, status, timeouts in (
            ([75], False, 200, [105]),
            ([106], False, 504, [105]),
            ([80, 20], True, 200, [105, 25]),
            ([104, 2], True, 504, [105, 1]),
        ):
            with self.subTest(durations=durations, repair=repair):
                clock = [1000.0]
                helper = helpers.ApiResponsesTests()
                body = helper._v3_midi_repair_body()
                valid = helper._v3_midi_repair_plan(out_of_bounds=False)
                invalid = helper._v3_midi_repair_plan(out_of_bounds=True)

                class Countdown:
                    def __init__(self, seconds, **kwargs):
                        self.deadline = clock[0] + seconds
                    def get_remaining_time_in_millis(self):
                        return int(max(0, self.deadline - clock[0]) * 1000)

                class ScheduledProvider:
                    name = 'offline-clock-provider'
                    def __init__(self, **kwargs):
                        self.attempt_count = 0
                        self.timeout_seconds = []
                    def forward_request(self, *, timeout_seconds, **kwargs):
                        self.timeout_seconds.append(timeout_seconds)
                        duration = durations[self.attempt_count]
                        self.attempt_count += 1
                        clock[0] += min(duration, timeout_seconds)
                        if duration >= timeout_seconds:
                            raise TimeoutError('synthetic deadline')
                        plan = invalid if repair and self.attempt_count == 1 else valid
                        return {'statusCode': 200, 'body': json.dumps(
                            bridge._provider_payload(plan, self.attempt_count))}

                with patch.object(bridge, '_LambdaContext', Countdown), \
                    patch.object(bridge, 'DeterministicProvider', ScheduledProvider), \
                    patch.object(bridge.api_responses.time, 'monotonic', side_effect=lambda: clock[0]), \
                    redirect_stdout(StringIO()):
                    backend = bridge.LocalBackend(scenario='success', delay_ms=0,
                        provider_timeout_seconds=105, transport_mode='long')
                    self.assertEqual(backend.lambda_timeout_seconds, 115)
                    result, measurement = backend.invoke(json.dumps(body), request_number=1)
                self.assertEqual(result['statusCode'], status)
                self.assertEqual(backend.providers[0].timeout_seconds, timeouts)
                self.assertEqual(backend.usage.reserve_count, 1)
                self.assertEqual(backend.usage.finalize_count, int(status == 200))
                self.assertEqual(backend.usage.release_count, int(status != 200))
                self.assertLessEqual(clock[0] - 1000, 105)
                self.assertLessEqual(measurement['provider_attempt_count'], 2)
        self.assertEqual(bridge.api_responses._V3_ABSOLUTE_MAX_PROVIDER_TIMEOUT_SECONDS, 105)

    def test_lambda_margin_still_applies(self):
        with patch.dict(os.environ, {
            'AI_V3_TIMEOUT_SECONDS': '105', 'AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS': '105',
        }):
            for remaining, expected in ((115000, 105), (11000, 9), (2999, 0)):
                self.assertEqual(bridge.api_responses._v3_request_timeout_seconds(
                    helpers._LambdaContext(remaining)), expected)
