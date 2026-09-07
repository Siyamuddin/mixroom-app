from __future__ import annotations

import copy
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import config as proxy_config  # noqa: E402
from common import auth as proxy_auth  # noqa: E402
from handlers import api_responses  # noqa: E402
from handlers import api_responses_v3_rest  # noqa: E402


ROUTE = "/v1/llm/v3/responses"


def _claims() -> dict:
    return {
        "iss": proxy_config.APP_AUTH_ISSUER,
        "aud": proxy_config.APP_AUTH_AUDIENCE,
        "sub": "rest-compatibility-user",
        "sid": "rest-compatibility-session",
        "token_use": "access",
    }


def _body(*, request_contract: str = "mixroom_v3_context_v2") -> dict:
    return {
        "request_contract": request_contract,
        "original_request": "Restart playback.",
        "conversation": [],
        "core_context": {
            "schema_version": "core_context_v3_prototype_1",
            "project": {"project_id": "rest-test-project", "bpm": 120},
        },
        "plan_schema_version": "plan_v3_prototype_2",
        "supported_command_types": ["transport.restart"],
        "resource_refs_enabled": True,
        "project_id": "rest-test-project",
        "prompt_trace_id": "rest-test-trace",
        "analytics_context": {
            "app_version": "test",
            "platform": "test",
            "ai_architecture": "v3",
        },
    }


def _http_event(body: dict, *, claims: dict | None = None) -> dict:
    return {
        "version": "2.0",
        "requestContext": {
            "requestId": "paired-request-id",
            "routeKey": f"POST {ROUTE}",
            "http": {"method": "POST", "path": ROUTE},
            "authorizer": {"jwt": {"claims": claims or _claims()}},
        },
        "rawPath": ROUTE,
        "headers": {"Authorization": "Bearer test-token"},
        "body": json.dumps(body),
        "isBase64Encoded": False,
    }


def _rest_event(
    body: dict,
    *,
    claims: dict | None = None,
    method: str = "POST",
    path: str = ROUTE,
) -> dict:
    return {
        "resource": ROUTE,
        "path": path,
        "httpMethod": method,
        "requestContext": {
            "requestId": "paired-request-id",
            "httpMethod": method,
            "authorizer": {"claims": claims or _claims()},
        },
        "headers": {"Authorization": "Bearer test-token"},
        "body": json.dumps(body),
        "isBase64Encoded": False,
    }


class _Reservation:
    allowed = True
    limit_reason = ""
    reserved_quota_prompts = 1
    reserved_grant_prompts = 0


class _UsageRepository:
    def __init__(self) -> None:
        self.reserve_calls: list[dict] = []
        self.release_calls: list[dict] = []
        self.finalize_calls: list[dict] = []
        self.log_calls: list[dict] = []

    def load_user_context(self, user_id: str) -> dict:
        return {"user_id": user_id, "subscription_tier": "free", "tier": "free"}

    def reserve_usage(self, user_id: str, **kwargs: object) -> _Reservation:
        self.reserve_calls.append({"user_id": user_id, **kwargs})
        return _Reservation()

    def release_usage(self, user_id: str, **kwargs: object) -> None:
        self.release_calls.append({"user_id": user_id, **kwargs})

    def finalize_usage(self, user_id: str, **kwargs: object) -> None:
        self.finalize_calls.append({"user_id": user_id, **kwargs})

    def log_usage_event(self, **kwargs: object) -> None:
        self.log_calls.append(dict(kwargs))

    def get_prompt_limit_status(self, user_id: str, **kwargs: object) -> dict:
        del user_id, kwargs
        return {
            "daily": {"used": 0, "limit": 100, "remaining": 100},
            "weekly": {"used": 0, "limit": 500, "remaining": 500},
            "can_submit": True,
            "blocked_by": "",
            "extra_prompt_bank": {"remaining": 0, "consumed_first": True},
        }


class _Provider:
    name = "fake-provider"

    def __init__(
        self,
        *,
        forward_error: Exception | None = None,
        response_bodies: list[dict] | None = None,
    ) -> None:
        self.request_body: dict | None = None
        self.timeout_seconds: int | None = None
        self.forward_error = forward_error
        self.response_bodies = copy.deepcopy(response_bodies or [])
        self.forward_calls = 0

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: dict,
        timeout_seconds: int,
    ) -> dict:
        self.forward_calls += 1
        self.request_body = copy.deepcopy(request_body)
        self.timeout_seconds = timeout_seconds
        if self.forward_error is not None:
            raise self.forward_error
        if self.response_bodies:
            response_body = self.response_bodies.pop(0)
        else:
            plan = {
                "schema_version": "plan_v3_prototype_2",
                "outcome": "respond",
                "user_message": "No project changes were needed.",
                "commands": [],
                "question_options": [],
            }
            response_body = {
                "id": "paired-provider-response",
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(plan),
                    }
                ],
                "usage": {
                    "input_tokens": 20,
                    "input_tokens_details": {"cached_tokens": 0},
                    "output_tokens": 10,
                    "output_tokens_details": {"reasoning_tokens": 2},
                    "total_tokens": 30,
                },
            }
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(response_body),
            "observability": {"provider_roundtrip_ms": 123},
        }


class _Context:
    aws_request_id = "paired-request-id"

    def get_remaining_time_in_millis(self) -> int:
        return 60_000


class V3RestAdapterTests(unittest.TestCase):
    @staticmethod
    def _without_elapsed_time(calls: list[dict]) -> list[dict]:
        normalized = copy.deepcopy(calls)
        for call in normalized:
            call.pop("proxy_handler_ms_total", None)
        return normalized

    def _invoke(
        self,
        entrypoint,
        event: dict,
        *,
        provider_error: Exception | None = None,
        provider_response_bodies: list[dict] | None = None,
        environment: dict[str, str] | None = None,
    ) -> tuple[dict, _Provider, _UsageRepository]:
        provider = _Provider(
            forward_error=provider_error,
            response_bodies=provider_response_bodies,
        )
        usage = _UsageRepository()
        configured_environment = {
            "AI_V3_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_V2_ENABLED": "true",
            "AI_V3_MODEL": "gpt-5.6-luna",
            "AI_V3_REASONING_EFFORT": "low",
        }
        configured_environment.update(environment or {})
        with (
            mock.patch.dict(
                os.environ,
                configured_environment,
                clear=False,
            ),
            mock.patch.object(api_responses, "_usage_repo", usage),
            mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"),
            mock.patch.object(api_responses, "get_provider", return_value=provider),
            mock.patch.object(
                api_responses,
                "get_ai_feature_runtime",
                side_effect=lambda _feature, fallback_model: {
                    "model": fallback_model,
                    "source": "test",
                },
            ),
            mock.patch.object(api_responses, "capture_event"),
            mock.patch.object(api_responses, "capture_exception"),
            redirect_stdout(StringIO()),
        ):
            response = entrypoint(event, _Context())
        return response, provider, usage

    def test_rest_and_http_v3_requests_are_behaviorally_equivalent(self) -> None:
        body = _body()
        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            _http_event(body),
        )
        rest_event = _rest_event(body)
        original_rest_event = copy.deepcopy(rest_event)
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            rest_event,
        )

        self.assertEqual(rest_event, original_rest_event)
        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_provider.request_body, http_provider.request_body)
        self.assertEqual(rest_provider.timeout_seconds, http_provider.timeout_seconds)
        self.assertEqual(rest_usage.reserve_calls, http_usage.reserve_calls)
        self.assertEqual(rest_usage.finalize_calls, http_usage.finalize_calls)
        self.assertEqual(rest_usage.release_calls, http_usage.release_calls)
        self.assertEqual(
            self._without_elapsed_time(rest_usage.log_calls),
            self._without_elapsed_time(http_usage.log_calls),
        )

    def test_rest_authorizer_claims_are_mapped_and_still_validated(self) -> None:
        normalized = api_responses_v3_rest.normalize_rest_event(_rest_event(_body()))
        self.assertEqual(
            normalized["requestContext"]["authorizer"]["jwt"]["claims"],
            _claims(),
        )

        invalid_claims = {**_claims(), "aud": "wrong-audience"}
        http_result, _, _ = self._invoke(
            api_responses.handler,
            _http_event(_body(), claims=invalid_claims),
        )
        result, provider, usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(_body(), claims=invalid_claims),
        )
        self.assertEqual(result, http_result)
        self.assertEqual(result["statusCode"], 401)
        self.assertIsNone(provider.request_body)
        self.assertEqual(usage.reserve_calls, [])

    def test_real_rest_event_authenticates_with_bearer_token_without_authorizer(self) -> None:
        event = _rest_event(_body())
        event["requestContext"].pop("authorizer")

        with (
            mock.patch.object(
                proxy_config,
                "APP_AUTH_SECRET_PARAMETER_NAME",
                "/mixroom/test/app-auth",
            ),
            mock.patch.object(
                proxy_auth,
                "_verify_native_token",
                return_value=_claims(),
            ) as verify_token,
        ):
            result, provider, usage = self._invoke(
                api_responses_v3_rest.handler,
                event,
            )

        self.assertEqual(result["statusCode"], 200)
        self.assertGreaterEqual(verify_token.call_count, 1)
        self.assertIsNotNone(provider.request_body)
        self.assertEqual(len(usage.reserve_calls), 1)
        self.assertEqual(len(usage.finalize_calls), 1)

    def test_rest_and_http_timeout_release_usage_identically(self) -> None:
        body = _body()
        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            _http_event(body),
            provider_error=TimeoutError("paired timeout"),
        )
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(body),
            provider_error=TimeoutError("paired timeout"),
        )

        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_result["statusCode"], 504)
        self.assertEqual(rest_provider.request_body, http_provider.request_body)
        self.assertEqual(rest_provider.timeout_seconds, http_provider.timeout_seconds)
        self.assertEqual(rest_usage.reserve_calls, http_usage.reserve_calls)
        self.assertEqual(rest_usage.release_calls, http_usage.release_calls)
        self.assertEqual(rest_usage.finalize_calls, [])
        self.assertEqual(http_usage.finalize_calls, [])
        self.assertEqual(
            self._without_elapsed_time(rest_usage.log_calls),
            self._without_elapsed_time(http_usage.log_calls),
        )

    def test_rest_and_http_upstream_failure_release_usage_identically(self) -> None:
        body = _body()
        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            _http_event(body),
            provider_error=RuntimeError("paired upstream failure"),
        )
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(body),
            provider_error=RuntimeError("paired upstream failure"),
        )

        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_result["statusCode"], 502)
        self.assertEqual(rest_provider.forward_calls, 1)
        self.assertEqual(http_provider.forward_calls, 1)
        self.assertEqual(rest_usage.reserve_calls, http_usage.reserve_calls)
        self.assertEqual(rest_usage.release_calls, http_usage.release_calls)
        self.assertEqual(rest_usage.finalize_calls, [])
        self.assertEqual(http_usage.finalize_calls, [])

    def test_rest_and_http_invalid_provider_output_settle_identically(self) -> None:
        invalid_response = {
            "id": "invalid-paired-provider-response",
            "output": [],
            "usage": {
                "input_tokens": 20,
                "output_tokens": 10,
                "total_tokens": 30,
            },
        }
        body = _body()
        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            _http_event(body),
            provider_response_bodies=[invalid_response],
        )
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(body),
            provider_response_bodies=[invalid_response],
        )

        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_provider.forward_calls, 1)
        self.assertEqual(http_provider.forward_calls, 1)
        self.assertEqual(rest_usage.reserve_calls, http_usage.reserve_calls)
        self.assertEqual(rest_usage.release_calls, http_usage.release_calls)
        self.assertEqual(rest_usage.finalize_calls, http_usage.finalize_calls)

    def test_rest_and_http_semantic_repair_settle_identically(self) -> None:
        unsafe_plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "respond",
            "user_message": "ORIGINAL_REQUEST_VERBATIM:\nRestart playback.",
            "commands": [],
            "question_options": [],
        }
        unsafe_response = {
            "id": "unsafe-paired-provider-response",
            "output": [
                {
                    "type": "function_call",
                    "name": "submit_plan_v3",
                    "arguments": json.dumps(unsafe_plan),
                }
            ],
            "usage": {
                "input_tokens": 20,
                "input_tokens_details": {"cached_tokens": 0},
                "output_tokens": 10,
                "output_tokens_details": {"reasoning_tokens": 2},
                "total_tokens": 30,
            },
        }
        body = _body()
        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            _http_event(body),
            provider_response_bodies=[unsafe_response],
        )
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(body),
            provider_response_bodies=[unsafe_response],
        )

        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_result["statusCode"], 200)
        self.assertEqual(rest_provider.forward_calls, 2)
        self.assertEqual(http_provider.forward_calls, 2)
        self.assertEqual(rest_usage.reserve_calls, http_usage.reserve_calls)
        self.assertEqual(rest_usage.release_calls, http_usage.release_calls)
        self.assertEqual(rest_usage.finalize_calls, http_usage.finalize_calls)
        self.assertEqual(len(rest_usage.finalize_calls), 1)

    def test_rest_and_http_malformed_json_fail_before_usage_identically(self) -> None:
        http_event = _http_event(_body())
        rest_event = _rest_event(_body())
        http_event["body"] = "{not-json"
        rest_event["body"] = "{not-json"

        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            http_event,
        )
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            rest_event,
        )

        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_result["statusCode"], 400)
        self.assertEqual(rest_provider.forward_calls, 0)
        self.assertEqual(http_provider.forward_calls, 0)
        self.assertEqual(rest_usage.reserve_calls, [])
        self.assertEqual(http_usage.reserve_calls, [])

    def test_rest_handler_isolated_to_post_contract_6_v3(self) -> None:
        wrong_path = api_responses_v3_rest.handler(
            _rest_event(_body(), path="/v1/llm/responses"),
            _Context(),
        )
        wrong_method = api_responses_v3_rest.handler(
            _rest_event(_body(), method="GET"),
            _Context(),
        )
        frozen_v1 = api_responses_v3_rest.handler(
            _rest_event(_body(request_contract="mixroom_v3_context_v1")),
            _Context(),
        )
        legacy = api_responses_v3_rest.handler(
            _rest_event({"model": "gpt-5.6-luna", "input": []}),
            _Context(),
        )

        self.assertEqual(wrong_path["statusCode"], 404)
        self.assertEqual(wrong_method["statusCode"], 405)
        for response in (frozen_v1, legacy):
            self.assertEqual(response["statusCode"], 400)
            self.assertEqual(
                json.loads(response["body"])["error"]["code"],
                "v3_request_contract_unsupported",
            )

    def test_rest_and_http_contract_6_kill_switch_fail_before_usage(self) -> None:
        environment = {"AI_V3_SERVER_CONTRACT_V2_ENABLED": "false"}
        http_result, http_provider, http_usage = self._invoke(
            api_responses.handler,
            _http_event(_body()),
            environment=environment,
        )
        rest_result, rest_provider, rest_usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(_body()),
            environment=environment,
        )

        self.assertEqual(rest_result, http_result)
        self.assertEqual(rest_result["statusCode"], 503)
        self.assertEqual(rest_provider.forward_calls, 0)
        self.assertEqual(http_provider.forward_calls, 0)
        self.assertEqual(rest_usage.reserve_calls, [])
        self.assertEqual(http_usage.reserve_calls, [])

    def test_unsupported_contract_does_not_bypass_authentication(self) -> None:
        invalid_claims = {**_claims(), "aud": "wrong-audience"}
        response, provider, usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(
                _body(request_contract="mixroom_v3_context_v1"),
                claims=invalid_claims,
            ),
        )

        self.assertEqual(response["statusCode"], 401)
        self.assertIsNone(provider.request_body)
        self.assertEqual(usage.reserve_calls, [])

    def test_long_path_timeout_ceiling_is_explicit_and_preserves_margin(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS": "55",
                "AI_V3_TIMEOUT_SECONDS": "55",
            },
            clear=False,
        ):
            for remaining_ms, expected in (
                (27_000, 25),
                (42_000, 40),
                (56_000, 54),
                (60_000, 55),
            ):
                with self.subTest(remaining_ms=remaining_ms):
                    context = _Context()
                    context.get_remaining_time_in_millis = lambda: remaining_ms
                    self.assertEqual(
                        api_responses._v3_request_timeout_seconds(context),
                        expected,
                    )

    def test_long_rest_handler_passes_55_second_deadline_to_provider(self) -> None:
        result, provider, usage = self._invoke(
            api_responses_v3_rest.handler,
            _rest_event(_body()),
            environment={
                "AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS": "55",
                "AI_V3_TIMEOUT_SECONDS": "55",
            },
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(provider.timeout_seconds, 55)
        self.assertEqual(len(usage.reserve_calls), 1)
        self.assertEqual(len(usage.finalize_calls), 1)
        self.assertEqual(usage.release_calls, [])

    def test_timeout_ceiling_cannot_exceed_long_path_safety_cap(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS": "999",
                "AI_V3_TIMEOUT_SECONDS": "999",
            },
            clear=False,
        ):
            self.assertEqual(
                api_responses._v3_request_timeout_seconds(_Context()),
                55,
            )


if __name__ == "__main__":
    unittest.main()
