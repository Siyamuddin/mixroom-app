from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_PATH = ROOT / "template.yaml"


def _resource_block(template: str, logical_id: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(logical_id)}:\n.*?(?=^  [A-Za-z0-9]+:\n|^Outputs:)",
        template,
    )
    if match is None:
        raise AssertionError(f"Missing resource {logical_id}.")
    return match.group(0)


class V3LongRestTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.template = TEMPLATE_PATH.read_text(encoding="utf-8")

    def test_released_http_api_resources_remain_byte_identical(self) -> None:
        expected = {
            "LlmApi": "22f9bce83c6cdafdf3553a5ff4d7fda1c7e320a5102c74e8fc3eb2a3b4c5aa7e",
            "ProxyResponsesFunction": "e10ec0ec84d2d6430bd13a9f319582298a94587cba3a0c6f30a3cfc6a8880c6d",
        }
        for logical_id, expected_hash in expected.items():
            block = _resource_block(self.template, logical_id)
            self.assertEqual(
                hashlib.sha256(block.encode("utf-8")).hexdigest(),
                expected_hash,
                logical_id,
            )

    def test_parallel_rest_api_contains_only_the_v3_contract_6_route(self) -> None:
        api = _resource_block(self.template, "V3LongRestApi")
        self.assertIn("Type: AWS::Serverless::Api", api)
        self.assertIn("Type: REGIONAL", api)
        self.assertIn("/v1/llm/v3/responses:", api)
        self.assertIn("timeoutInMillis: 120000", api)
        self.assertNotIn("/v1/llm/responses:", api)
        self.assertNotIn("/v1/llm/limits:", api)
        self.assertNotIn("/v1/llm/conversation-events:", api)
        self.assertIn(
            "ThrottlingBurstLimit: !Ref V3LongApiThrottleBurstLimit",
            api,
        )
        self.assertIn(
            "ThrottlingRateLimit: !Ref V3LongApiThrottleRateLimit",
            api,
        )
        self.assertNotIn("ThrottlingBurstLimit: !Ref ApiThrottleBurstLimit", api)
        self.assertNotIn("ThrottlingRateLimit: !Ref ApiThrottleRateLimit", api)

    def test_long_api_has_a_concurrency_safe_rollout_envelope(self) -> None:
        self.assertRegex(
            self.template,
            r"(?ms)^  V3LongApiThrottleBurstLimit:\n"
            r"    Type: Number\n"
            r"    Default: 5\n"
            r"    MinValue: 1\n"
            r"    MaxValue: 20$",
        )
        self.assertRegex(
            self.template,
            r"(?ms)^  V3LongApiThrottleRateLimit:\n"
            r"    Type: Number\n"
            r"    Default: 1\n"
            r"    MinValue: 0\.1\n"
            r"    MaxValue: 1$",
        )

        lambda_timeout_seconds = 115
        maximum_rate_per_second = 1
        maximum_burst = 20
        minimum_rollout_account_concurrency = 155
        maximum_long_path_in_flight = (
            lambda_timeout_seconds * maximum_rate_per_second
            + maximum_burst
        )
        self.assertLessEqual(maximum_long_path_in_flight, 135)
        self.assertGreaterEqual(
            minimum_rollout_account_concurrency - maximum_long_path_in_flight,
            20,
        )

    def test_long_lambda_is_isolated_and_uses_staggered_deadlines(self) -> None:
        function = _resource_block(self.template, "V3LongResponsesFunction")
        self.assertIn("Handler: handlers/api_responses_v3_rest.handler", function)
        self.assertIn("Timeout: 115", function)
        self.assertIn("AI_V3_TIMEOUT_SECONDS: 105", function)
        self.assertIn("AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS: 105", function)
        self.assertNotIn("Type: HttpApi", function)
        self.assertNotIn("mixroom_v3_context_v1", function)
        self.assertRegex(
            self.template,
            r"(?ms)^  V3MaxRequestBytes:\n"
            r"    Type: Number\n"
            r"    Default: 4500000$",
        )
        self.assertIn("V3_MAX_REQUEST_BYTES: !Ref V3MaxRequestBytes", self.template)

        permission = _resource_block(
            self.template,
            "V3LongRestApiInvokePermission",
        )
        self.assertIn("Principal: apigateway.amazonaws.com", permission)
        self.assertIn("FunctionName: !Ref V3LongResponsesFunction", permission)
        self.assertIn("/POST/v1/llm/v3/responses", permission)

    def test_long_lambda_has_the_existing_response_lambda_permissions(self) -> None:
        existing = _resource_block(self.template, "ProxyResponsesFunction")
        long_running = _resource_block(self.template, "V3LongResponsesFunction")
        existing_policies = existing.split("      Policies:\n", 1)[1].split(
            "      Events:\n",
            1,
        )[0]
        long_policies = long_running.split("      Policies:\n", 1)[1]
        self.assertEqual(long_policies.rstrip(), existing_policies.rstrip())

    def test_long_endpoint_is_not_the_existing_client_output(self) -> None:
        outputs = self.template.split("\nOutputs:\n", 1)[1]
        self.assertIn("ApiBaseUrl:", outputs)
        self.assertIn("${LlmApi}", outputs)
        self.assertIn("V3LongApiBaseUrl:", outputs)
        self.assertIn("${V3LongRestApi}", outputs)


if __name__ == "__main__":
    unittest.main()
