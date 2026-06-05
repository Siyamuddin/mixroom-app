from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import config as proxy_config  # noqa: E402
from handlers import api_responses  # noqa: E402


def _authed_event(
    body: str = "{}",
    *,
    claims: dict | None = None,
    method: str = "POST",
    path: str = "/v1/llm/responses",
) -> dict:
    return {
        "requestContext": {
            "http": {
                "method": method,
            },
            "routeKey": f"{method} {path}",
            "authorizer": {
                "jwt": {
                    "claims": claims
                    or {
                        "iss": proxy_config.APP_AUTH_ISSUER,
                        "aud": proxy_config.APP_AUTH_AUDIENCE,
                        "sub": "user-123",
                        "sid": "session-123",
                        "token_use": "access",
                    },
                }
            }
        },
        "rawPath": path,
        "headers": {
            "Authorization": "Bearer test-token",
        },
        "body": body,
        "isBase64Encoded": False,
    }


class _FakeProvider:
    def __init__(
        self,
        *,
        name: str = "fake-provider",
        response_body: dict | None = None,
        status_code: int = 200,
        forward_error: Exception | None = None,
    ) -> None:
        self.name = name
        self.api_key: str | None = None
        self.request_body: dict | None = None
        self.timeout_seconds: int | None = None
        self._response_body = response_body or {"ok": True}
        self._status_code = status_code
        self._forward_error = forward_error

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: dict,
        timeout_seconds: int,
    ) -> dict:
        if self._forward_error is not None:
            raise self._forward_error
        self.api_key = api_key
        self.request_body = request_body
        self.timeout_seconds = timeout_seconds
        return {
            "statusCode": self._status_code,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(self._response_body),
        }


class _ReservationResult:
    def __init__(
        self,
        allowed: bool,
        limit_reason: str = "",
        *,
        reserved_quota_prompts: int = 1,
        reserved_grant_prompts: int = 0,
    ) -> None:
        self.allowed = allowed
        self.limit_reason = limit_reason
        self.reserved_quota_prompts = reserved_quota_prompts
        self.reserved_grant_prompts = reserved_grant_prompts


class _FakeUsageRepo:
    def __init__(self) -> None:
        self.user_context = {
            "user_id": "user-123",
            "subscription_tier": "free",
            "tier": "free",
        }
        self.reservation_result = _ReservationResult(True, "")
        self.reserve_calls: list[dict] = []
        self.release_calls: list[dict] = []
        self.finalize_calls: list[dict] = []
        self.log_calls: list[dict] = []
        self.prompt_rate_limit = {
            "daily": {
                "used": 0,
                "limit": 100,
                "remaining": 100,
                "resets_at": "2026-03-18T00:00:00+00:00",
            },
            "weekly": {
                "used": 0,
                "limit": 500,
                "remaining": 500,
                "resets_at": "2026-03-23T00:00:00+00:00",
            },
            "can_submit": True,
            "blocked_by": "",
            "extra_prompt_bank": {
                "remaining": 0,
                "consumed_first": True,
            },
        }

    def load_user_context(self, user_id: str) -> dict:
        payload = dict(self.user_context)
        payload["user_id"] = user_id
        return payload

    def reserve_usage(self, user_id: str, **kwargs: object) -> _ReservationResult:
        self.reserve_calls.append({"user_id": user_id, **kwargs})
        return self.reservation_result

    def release_usage(self, user_id: str, **kwargs: object) -> None:
        self.release_calls.append({"user_id": user_id, **kwargs})

    def finalize_usage(self, user_id: str, **kwargs: object) -> None:
        self.finalize_calls.append({"user_id": user_id, **kwargs})

    def log_usage_event(self, **kwargs: object) -> None:
        self.log_calls.append(dict(kwargs))

    def get_prompt_limit_status(self, user_id: str, **kwargs: object) -> dict:
        return json.loads(json.dumps(self.prompt_rate_limit))


class ApiResponsesTests(unittest.TestCase):
    def _tool_action_types(self, daw_tool):
        actions = daw_tool["parameters"]["properties"]["actions"]
        items = actions["items"]
        if "properties" in items:
            return items["properties"]["type"]["enum"]

        allowed = []
        for variant in items.get("oneOf", []):
            type_schema = variant.get("properties", {}).get("type", {})
            if "enum" in type_schema:
                allowed.extend(type_schema["enum"])
            elif "const" in type_schema:
                allowed.append(type_schema["const"])
        return allowed

    def setUp(self) -> None:
        api_responses._secret_cache = None
        api_responses._secret_cache_loaded_at = None
        self.fake_usage_repo = _FakeUsageRepo()
        self.usage_repo_patcher = mock.patch.object(
            api_responses,
            "_usage_repo",
            self.fake_usage_repo,
        )
        self.usage_repo_patcher.start()
        self.addCleanup(self.usage_repo_patcher.stop)

    def test_handler_requires_authenticated_user(self) -> None:
        event = {
            "headers": {},
            "body": json.dumps({"input": []}),
            "isBase64Encoded": False,
        }

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 401)

    def test_handler_rejects_unsigned_header_only_tokens_when_authorizer_claims_are_missing(self) -> None:
        event = {
            "requestContext": {
                "http": {"method": "POST"},
                "routeKey": "POST /v1/llm/responses",
                "authorizer": {},
            },
            "headers": {
                "Authorization": "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJhdHRhY2tlciJ9.",
            },
            "body": json.dumps({"input": [{"role": "user", "content": "hello"}]}),
            "isBase64Encoded": False,
        }

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 401)

    def test_handler_rejects_invalid_json(self) -> None:
        event = _authed_event("{not-json")

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("Invalid JSON", result["body"])

    def test_handler_rejects_large_body(self) -> None:
        event = _authed_event(json.dumps({"x": "a" * 50}))

        with mock.patch.dict(os.environ, {"MAX_REQUEST_BYTES": "10"}, clear=False):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 413)

    def test_handler_builds_server_owned_request_for_mixroom_payload(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [
                        {"role": "assistant", "content": "Previous assistant reply."}
                    ],
                    "user_text": "Make the vocals clearer.",
                    "project_snapshot": "Track 1: Lead Vocal",
                    "selection_snapshot": "Row 1 selected",
                    "pending_mix": {"mode": "propose", "actions": []},
                    "instructions": "client-owned prompt should be ignored",
                    "tools": [{"name": "client_tool_should_be_ignored"}],
                    "request_overrides": {"model": "client-model"},
                }
            )
        )

        with mock.patch.dict(
            os.environ,
            {
                "LLM_MODEL": "server-model",
                "ALLOW_CLIENT_MODEL_OVERRIDE": "false",
            },
            clear=False,
        ):
            with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
                with mock.patch.object(api_responses, "get_provider", return_value=provider):
                    result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(provider.api_key, "sk-test")
        assert provider.request_body is not None
        self.assertEqual(provider.request_body["model"], "server-model")
        self.assertIn("AI Co-Producer", provider.request_body["instructions"])
        self.assertEqual(
            provider.request_body["prompt_cache_key"],
            "mixroom-daw-v20260422a:ai_chat:c49fea7425fa",
        )
        self.assertEqual(provider.request_body["prompt_cache_retention"], "in_memory")
        self.assertEqual(provider.request_body["tools"][0]["name"], "informational_response")
        self.assertIn(
            "For recommendation or discovery requests",
            provider.request_body["instructions"],
        )
        self.assertIn(
            "Brief factual questions about public songs, artists, genres, or styles are",
            provider.request_body["instructions"],
        )
        self.assertIn(
            "Do not imitate or transcribe named copyrighted works",
            provider.request_body["instructions"],
        )
        self.assertIn(
            "across languages, default to a polite neutral professional register",
            provider.request_body["instructions"],
        )
        self.assertIn(
            "Prefer execution over permission loops.",
            provider.request_body["instructions"],
        )
        self.assertEqual(
            provider.request_body["messages"][0],
            {"role": "user", "content": "PROJECT_SNAPSHOT:\nTrack 1: Lead Vocal"},
        )
        self.assertEqual(
            provider.request_body["messages"][-1],
            {"role": "user", "content": "Make the vocals clearer."},
        )

    def test_handler_includes_client_entitlement_policy_in_prompt(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "add shimmer and create a bassline",
                    "project_snapshot": "Track 1: Audio",
                    "library_snapshot": "instrument_id=mixroom.basic_synth",
                    "client_context": {
                        "subscription_plan": "free",
                        "max_rows": 5,
                        "current_rows": 5,
                        "plugin_access": "core_built_in_only",
                        "row_creation_policy": "Reuse rows at or below row_index 4.",
                        "allowed_builtin_effects": ["Gain", "EQ 3-Band", "Delay"],
                        "allowed_instrument_ids": ["mixroom.basic_synth"],
                    },
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        instructions = provider.request_body["instructions"]
        self.assertIn("CLIENT ENTITLEMENT POLICY", instructions)
        self.assertIn("Maximum project row_index is 4", instructions)
        self.assertIn("core_built_in_only", instructions)
        self.assertIn("Gain, EQ 3-Band, Delay", instructions)
        self.assertIn("mixroom.basic_synth", instructions)
        self.assertNotEqual(
            provider.request_body["prompt_cache_key"],
            "mixroom-daw-v20260422a:ai_chat:c49fea7425fa",
        )

    def test_handler_applies_remote_ai_runtime_overrides(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "Make the vocals clearer.",
                    "project_snapshot": "Track 1: Lead Vocal",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                with mock.patch.object(
                    api_responses,
                    "get_ai_feature_runtime",
                    return_value={
                        "feature": "ai_chat",
                        "model": "gpt-5-mini",
                        "system_prompt": "Remote prompt override",
                        "temperature": 0.4,
                        "reasoning": {"effort": "medium"},
                        "max_output_tokens": 777,
                        "prompt_cache_retention": "24h",
                        "has_model_override": True,
                        "has_system_prompt_override": True,
                        "has_temperature_override": True,
                        "has_reasoning_override": True,
                        "has_max_output_tokens_override": True,
                        "has_prompt_cache_retention_override": True,
                    },
                ):
                    result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        self.assertEqual(provider.request_body["model"], "gpt-5-mini")
        self.assertEqual(provider.request_body["instructions"], "Remote prompt override")
        self.assertEqual(provider.request_body["max_output_tokens"], 777)
        self.assertEqual(provider.request_body["reasoning"], {"effort": "medium"})
        self.assertEqual(provider.request_body["prompt_cache_retention"], "24h")
        self.assertNotIn("temperature", provider.request_body)

    def test_handler_includes_observability_payload_and_logs_trace_fields(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "gpt-4.1-mini",
                "output": [
                    {
                        "type": "function_call",
                        "name": "informational_response",
                        "arguments": {
                            "message": "Done.",
                            "cancels_pending": False,
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 10,
                    "output_tokens": 5,
                    "total_tokens": 15,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "prompt_trace_id": "trace-123",
                    "client_context": {
                        "app_version": "1.0.8+14",
                        "platform": "android",
                    },
                    "input": [
                        {
                            "role": "user",
                            "content": "Help me.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload["observability"]["prompt_trace_id"], "trace-123")
        self.assertTrue(payload["observability"]["runtime_config_fingerprint"])
        self.assertEqual(payload["observability"]["provider_response_id"], "resp_123")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["prompt_trace_id"], "trace-123")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["app_version"], "1.0.8+14")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["platform"], "android")

    def test_handler_uses_video_contract_for_video_editor_feature(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "video_editor_chat",
                    "conversation": [
                        {"role": "assistant", "content": "Previous assistant reply."}
                    ],
                    "user_text": "Split the selected clip at the playhead.",
                    "project_snapshot": '{"project":"video"}',
                    "selection_snapshot": '{"selected_clip_id":"clip-1"}',
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        self.assertIn("video timeline assistant", provider.request_body["instructions"])
        self.assertEqual(provider.request_body["tools"][1]["name"], "video_editor_actions")
        self.assertEqual(
            provider.request_body["messages"][-1],
            {"role": "user", "content": "Split the selected clip at the playhead."},
        )

    def test_handler_omits_temperature_for_gpt5_models(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "user_text": "Make the vocals clearer.",
                    "project_snapshot": "Track 1: Lead Vocal",
                    "request_overrides": {"model": "gpt-5-mini"},
                }
            )
        )

        with mock.patch.dict(
            os.environ,
            {
                "LLM_MODEL": "gpt-4.1-mini",
                "ALLOW_CLIENT_MODEL_OVERRIDE": "true",
            },
            clear=False,
        ):
            with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
                with mock.patch.object(api_responses, "get_provider", return_value=provider):
                    result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        self.assertEqual(provider.request_body["model"], "gpt-5-mini")
        self.assertNotIn("temperature", provider.request_body)
        self.assertEqual(provider.request_body["reasoning"], {"effort": "minimal"})
        self.assertEqual(provider.request_body["prompt_cache_retention"], "in_memory")

    def test_handler_logs_prompt_cache_hit_telemetry(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "gpt-4.1-mini",
                "usage": {
                    "input_tokens": 8099,
                    "output_tokens": 161,
                    "total_tokens": 8260,
                    "input_tokens_details": {"cached_tokens": 7424},
                },
                "output": [
                    {
                        "type": "function_call",
                        "name": "informational_response",
                        "arguments": {
                            "message": "Added a subtle delay effect to the lead vocal track.",
                            "cancels_pending": False,
                        },
                    }
                ],
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "user_text": "Add a subtle delay to the vocal.",
                    "project_snapshot": "Track 1: Lead Vocal",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                with mock.patch.object(api_responses, "log_request_complete") as log_request:
                    result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        log_request.assert_called_once()
        request_context = log_request.call_args.kwargs["request_context"]
        self.assertEqual(
            request_context["prompt_cache_key"],
            "mixroom-daw-v20260422a:ai_chat:c49fea7425fa",
        )
        self.assertEqual(request_context["prompt_cache_retention"], "in_memory")
        self.assertEqual(request_context["prompt_tokens"], 8099)
        self.assertEqual(request_context["cached_prompt_tokens"], 7424)
        self.assertTrue(request_context["prompt_cache_hit"])

    def test_handler_pins_server_model_before_forwarding(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "model": "client-model",
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.dict(
            os.environ,
            {
                "LLM_MODEL": "server-model",
                "ALLOW_CLIENT_MODEL_OVERRIDE": "false",
            },
            clear=False,
        ):
            with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
                with mock.patch.object(api_responses, "get_provider", return_value=provider):
                    result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(provider.api_key, "sk-test")
        assert provider.request_body is not None
        self.assertEqual(provider.request_body["model"], "server-model")

    def test_handler_drops_unknown_fields_before_forwarding(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "model": "client-model",
                    "input": [{"role": "user", "content": "hi"}],
                    "tools": [],
                    "unexpected": "drop-me",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        self.assertNotIn("unexpected", provider.request_body)
        self.assertEqual(
            provider.request_body["messages"],
            [{"role": "user", "content": "hi"}],
        )

    def test_handler_rejects_invalid_input_shape(self) -> None:
        event = _authed_event(json.dumps({"input": "not-a-list"}))

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("'input' must be a non-empty list.", result["body"])

    def test_handler_rejects_invalid_structured_payload(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "conversation": "not-a-list",
                    "user_text": "Hi",
                    "project_snapshot": "Track 1",
                }
            )
        )

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("'conversation' must be a list.", result["body"])

    def test_handler_rejects_unknown_provider(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.dict(os.environ, {"LLM_PROVIDER": "llama"}, clear=False):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 500)
        self.assertIn("Unsupported LLM provider", result["body"])

    def test_handler_uses_generic_timeout_env(self) -> None:
        provider = _FakeProvider()
        event = _authed_event(
            json.dumps(
                {
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.dict(os.environ, {"LLM_TIMEOUT_SECONDS": "45"}, clear=False):
            with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
                with mock.patch.object(api_responses, "get_provider", return_value=provider):
                    result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(provider.timeout_seconds, 45)

    def test_handler_rejects_unknown_ai_feature(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "made_up_feature",
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("Unsupported AI feature", result["body"])

    def test_handler_returns_429_when_daily_limit_is_hit(self) -> None:
        provider = _FakeProvider()
        self.fake_usage_repo.reservation_result = _ReservationResult(False, "daily_prompts")
        self.fake_usage_repo.prompt_rate_limit = {
            "daily": {
                "used": 50,
                "limit": 50,
                "remaining": 0,
                "resets_at": "2026-03-18T00:00:00+00:00",
            },
            "weekly": {
                "used": 120,
                "limit": 350,
                "remaining": 230,
                "resets_at": "2026-03-23T00:00:00+00:00",
            },
            "can_submit": False,
            "blocked_by": "daily_prompts",
        }
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "assistant_chat",
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 429)
        self.assertEqual(provider.request_body, None)
        self.assertEqual(len(self.fake_usage_repo.reserve_calls), 1)
        reserve_call = self.fake_usage_repo.reserve_calls[0]
        self.assertEqual(reserve_call["reserved_prompts"], 1)
        self.assertEqual(reserve_call["daily_prompt_limit"], 200)
        self.assertEqual(reserve_call["weekly_prompt_limit"], 600)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "rate_limited")
        payload = json.loads(result["body"])
        self.assertEqual(payload["error"], "prompt_rate_limit_hit")
        self.assertEqual(payload["prompt_rate_limit"]["blocked_by"], "daily_prompts")

    def test_handler_returns_prompt_limit_status_for_authenticated_get(self) -> None:
        self.fake_usage_repo.prompt_rate_limit = {
            "daily": {
                "used": 12,
                "limit": 50,
                "remaining": 38,
                "resets_at": "2026-03-18T00:00:00+00:00",
            },
            "weekly": {
                "used": 80,
                "limit": 350,
                "remaining": 270,
                "resets_at": "2026-03-23T00:00:00+00:00",
            },
            "can_submit": True,
            "blocked_by": "",
        }
        event = _authed_event(method="GET", path="/v1/llm/limits")

        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload["prompt_rate_limit"]["daily"]["remaining"], 38)
        self.assertEqual(payload["prompt_rate_limit"]["weekly"]["remaining"], 270)

    def test_handler_maps_upstream_429_to_service_unavailable(self) -> None:
        provider = _FakeProvider(
            status_code=429,
            response_body={
                "error": {
                    "message": "Rate limit reached for model.",
                    "type": "rate_limit_exceeded",
                    "code": "rate_limit_exceeded",
                }
            },
        )
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "assistant_chat",
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 503)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "failed")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["error_code"], "rate_limit_exceeded")
        payload = json.loads(result["body"])
        self.assertEqual(payload["code"], "llm_upstream_rate_limited")
        self.assertNotEqual(payload["error"], "prompt_rate_limit_hit")

    def test_handler_finalizes_actual_usage_after_success(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "mode": "execute",
                            "assistant_message": "Applied the requested mix changes.",
                            "actions": [
                                {
                                    "goal": {
                                        "type": "mix_request",
                                        "intents": [
                                            {
                                                "kind": "gain",
                                                "direction": "up",
                                                "descriptor": "null",
                                                "confidence": 0.92,
                                            }
                                        ],
                                        "target": {
                                            "row_index": 0,
                                            "scope": "row",
                                            "confidence": 0.95,
                                        },
                                        "intensity": 0.45,
                                    }
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 320,
                    "output_tokens": 180,
                    "total_tokens": 500,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "assistant_chat",
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)
        finalize_call = self.fake_usage_repo.finalize_calls[0]
        self.assertEqual(finalize_call["reserved_prompts"], 1)
        self.assertEqual(finalize_call["actual_prompts"], 1)
        self.assertEqual(finalize_call["actual_tokens"], 500)
        self.assertEqual(finalize_call["actual_credits"], 2)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "success")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["credits_charged"], 2)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["resolved_tool"], "mix_model_request")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["provider_response_id"], "resp_123")
        payload = json.loads(result["body"])
        self.assertEqual(payload["prompt_rate_limit"]["daily"]["limit"], 100)

    def test_handler_keeps_valid_actions_when_sibling_action_is_invalid(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_partial_actions",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "mode": "execute",
                            "assistant_message": "Applied the usable mix change.",
                            "actions": [
                                {
                                    "goal": {
                                        "type": "mix_request",
                                        "intents": [
                                            {
                                                "kind": "gain",
                                                "direction": "up",
                                                "confidence": 0.9,
                                            }
                                        ],
                                        "target": {
                                            "row_index": 0,
                                            "scope": "row",
                                            "confidence": 0.95,
                                        },
                                        "intensity": 0.35,
                                    }
                                },
                                {
                                    "goal": {
                                        "type": "mix_request",
                                        "intents": [
                                            {
                                                "kind": "not_a_real_intent",
                                                "direction": "up",
                                                "confidence": 0.5,
                                            }
                                        ],
                                        "target": {
                                            "row_index": 1,
                                            "scope": "row",
                                            "confidence": 0.75,
                                        },
                                    }
                                },
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 320,
                    "output_tokens": 180,
                    "total_tokens": 500,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "assistant_chat",
                    "input": [{"role": "user", "content": "raise the vocal"}],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "mix_model_request")
        self.assertNotIn("soft_error", payload)
        self.assertEqual(len(output["arguments"]["actions"]), 1)
        self.assertEqual(
            output["arguments"]["actions"][0]["goal"]["intents"][0]["kind"],
            "gain",
        )
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 0)

    def test_handler_repairs_wrapped_master_clipper_tool_output(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "value": json.dumps(
                                {
                                    "mode": "execute",
                                    "assistant_message": "Enhancé la calidad para que suene más sofisticado.",
                                    "actions": [
                                        {
                                            "goal": {
                                                "type": "mix_request",
                                                "intents": [
                                                    {
                                                        "kind": "limiter",
                                                        "direction": "up",
                                                        "descriptor": "null",
                                                        "confidence": 0.94,
                                                    }
                                                ],
                                                "target": {
                                                    "scope": "master",
                                                    "row_index": -1,
                                                    "role": None,
                                                    "confidence": 0.91,
                                                },
                                                "intensity": 0.42,
                                            }
                                        }
                                    ],
                                }
                            )
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Put a clipper on the master bus.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "mix_model_request")
        arguments = output["arguments"]
        self.assertEqual(arguments["assistant_message"], "Applied the requested mix changes.")
        self.assertEqual(arguments["actions"][0]["goal"]["intents"][0]["kind"], "clipper")
        self.assertEqual(arguments["actions"][0]["goal"]["target"]["scope"], "master")
        self.assertNotIn("row_index", arguments["actions"][0]["goal"]["target"])
        self.assertNotIn("role", arguments["actions"][0]["goal"]["target"])

    def test_handler_repairs_legacy_mix_goal_type_to_mix_request(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_legacy_goal_type",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "mode": "execute",
                            "assistant_message": "Added some space to the bass.",
                            "actions": [
                                {
                                    "goal": {
                                        "type": "reverb",
                                        "intents": [
                                            {
                                                "kind": "reverb",
                                                "direction": "up",
                                                "confidence": 0.72,
                                            }
                                        ],
                                        "target": {
                                            "scope": "row",
                                            "row_index": 2,
                                            "confidence": 0.84,
                                        },
                                        "intensity": 0.18,
                                        "execution_profile": "creative_bold",
                                        "audibility": "obvious",
                                        "style_tags": ["washed", "club"],
                                        "destructive_ok": False,
                                    }
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 120,
                    "output_tokens": 80,
                    "total_tokens": 200,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "add more wetness",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "mix_model_request")
        arguments = output["arguments"]
        self.assertEqual(arguments["actions"][0]["goal"]["type"], "mix_request")
        self.assertEqual(
            arguments["actions"][0]["goal"]["execution_profile"], "creative_bold"
        )
        self.assertEqual(arguments["actions"][0]["goal"]["audibility"], "obvious")
        self.assertEqual(
            arguments["actions"][0]["goal"]["style_tags"], ["washed", "club"]
        )
        self.assertFalse(arguments["actions"][0]["goal"]["destructive_ok"])
        self.assertEqual(arguments["actions"][0]["goal"]["intents"][0]["kind"], "reverb")

    def test_handler_preserves_reference_mix_goal_fields(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_reference_goal",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "mode": "execute",
                            "assistant_message": "Matching the project toward the reference track.",
                            "actions": [
                                {
                                    "goal": {
                                        "type": "balance",
                                        "intents": [
                                            {
                                                "kind": "balance",
                                                "confidence": 0.88,
                                            }
                                        ],
                                        "target": {
                                            "scope": "row",
                                            "row_index": 1,
                                            "confidence": 0.9,
                                        },
                                        "reference_target": {
                                            "prefer_selected": True,
                                            "confidence": 0.82,
                                        },
                                        "reference_mode": "full_mix",
                                        "reference_closeness": "close",
                                        "intensity": 0.42,
                                        "execution_profile": "creative_bold",
                                        "audibility": "obvious",
                                        "style_tags": ["wide", "glue"],
                                        "destructive_ok": False,
                                    }
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 120,
                    "output_tokens": 80,
                    "total_tokens": 200,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "mix this close to the reference track",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "mix_model_request")
        goal = output["arguments"]["actions"][0]["goal"]
        self.assertEqual(goal["type"], "mix_request")
        self.assertTrue(goal["reference_target"]["prefer_selected"])
        self.assertEqual(goal["reference_target"]["confidence"], 0.82)
        self.assertEqual(goal["reference_mode"], "full_mix")
        self.assertEqual(goal["reference_closeness"], "close")
        self.assertEqual(goal["execution_profile"], "creative_bold")
        self.assertEqual(goal["audibility"], "obvious")
        self.assertEqual(goal["style_tags"], ["wide", "glue"])
        self.assertFalse(goal["destructive_ok"])

    def test_handler_normalizes_legacy_midi_note_payload_shape(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_midi_notes",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll replace the current notes.",
                            "actions": [
                                {
                                    "type": "midi_compose",
                                    "data": {
                                        "operation": "replace_notes",
                                        "target": {"prefer_selected": True},
                                        "notes": [
                                            {
                                                "pitch": "C4",
                                                "start_measure": 1,
                                                "duration_measures": 1,
                                                "velocity": 82,
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 110,
                    "output_tokens": 90,
                    "total_tokens": 200,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "replace the selected midi notes",
                    "project_snapshot": "Track 1: MIDI Chords",
                    "selection_snapshot": "selected_clip_indices=0",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        note = output["arguments"]["actions"][0]["data"]["notes"][0]
        self.assertEqual(note["pitch"], 60)
        self.assertEqual(note["start_beat"], 0.0)
        self.assertEqual(note["length_beats"], 4.0)
        self.assertAlmostEqual(note["velocity"], 82 / 127.0, places=4)

    def test_handler_accepts_create_clip_with_chord_pitch_blocks(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_midi_create_clip",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll lay down jazz chords on piano.",
                            "actions": [
                                {
                                    "type": "midi_compose",
                                    "data": {
                                        "operation": "create_clip",
                                        "target": {"row_index": 0},
                                        "instrument_id": "sfz.vsco.upright_piano",
                                        "length_measures": 8,
                                        "notes": [
                                            {
                                                "measure": 1,
                                                "beat": 1,
                                                "duration_beats": 4,
                                                "pitches": ["C3", "E3", "G3", "B3"],
                                                "velocity": 90,
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 120,
                    "output_tokens": 88,
                    "total_tokens": 208,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "jazz chords",
                    "project_snapshot": "Track 1: MIDI Chords",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "midi_compose")
        self.assertEqual(action["data"]["operation"], "create_clip")
        note = action["data"]["notes"][0]
        self.assertEqual(note["pitches"], [48, 52, 55, 59])
        self.assertEqual(note["start_beat"], 0.0)
        self.assertEqual(note["length_beats"], 4.0)
        self.assertAlmostEqual(note["velocity"], 90 / 127.0, places=4)

    def test_handler_accepts_time_beats_alias_for_midi_notes(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_midi_time_beats",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll reharmonize that clip in minor.",
                            "actions": [
                                {
                                    "type": "midi_compose",
                                    "data": {
                                        "operation": "replace_notes",
                                        "target": {"prefer_selected": True},
                                        "notes": [
                                            {
                                                "time_beats": 12,
                                                "lengthBeats": 4,
                                                "pitch": "E3",
                                                "velocity": 75,
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 80,
                    "output_tokens": 60,
                    "total_tokens": 140,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "make minor key now",
                    "project_snapshot": "Track 1: MIDI Chords",
                    "selection_snapshot": "selected_clip_indices=0",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        note = output["arguments"]["actions"][0]["data"]["notes"][0]
        self.assertEqual(note["start_beat"], 12.0)
        self.assertEqual(note["length_beats"], 4.0)
        self.assertEqual(note["pitch"], 52)

    def test_handler_accepts_audio_to_midi_without_note_payload(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_audio_to_midi",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll convert that vocal to MIDI.",
                            "actions": [
                                {
                                    "type": "midi_compose",
                                    "data": {
                                        "operation": "audio_to_midi",
                                        "target": {"prefer_selected": True},
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 72,
                    "output_tokens": 44,
                    "total_tokens": 116,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "convert this vocal to midi",
                    "project_snapshot": "Track 1: Lead Vocal",
                    "selection_snapshot": "selected_clip_indices=0",
                    "client_context": {
                        "ai_capabilities": ["daw.midi_compose.audio_to_midi"],
                    },
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "midi_compose")
        self.assertEqual(action["data"]["operation"], "convert_audio_to_midi")
        self.assertNotIn("notes", action["data"])
        self.assertNotIn("progression", action["data"])

    def test_handler_soft_fails_project_edit_for_legacy_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_project_edit_legacy",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Setting the project tempo to 156 BPM.",
                            "actions": [
                                {
                                    "type": "project_edit",
                                    "data": {
                                        "operation": "set_bpm",
                                        "tempo_bpm": 156,
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 80,
                    "output_tokens": 40,
                    "total_tokens": 120,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "808 beat 156 bpm",
                    "project_snapshot": "Track 1: empty",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "informational_response")
        self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")

    def test_handler_preserves_project_edit_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_project_edit_capable",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Setting the project tempo to 156 BPM.",
                            "actions": [
                                {
                                    "type": "project_edit",
                                    "data": {
                                        "operation": "set_bpm",
                                        "bpm": "156",
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 80,
                    "output_tokens": 40,
                    "total_tokens": 120,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "set bpm to 156",
                    "project_snapshot": "Track 1: empty",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.project_edit.set_tempo"],
                    },
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "project_edit")
        self.assertEqual(action["data"]["operation"], "set_tempo")
        self.assertEqual(action["data"]["tempo_bpm"], 156.0)
        tool_defs = provider.request_body["tools"]
        daw_tool = next(
            tool for tool in tool_defs if tool.get("name") == "daw_assistant_actions"
        )
        action_types = self._tool_action_types(daw_tool)
        self.assertIn("project_edit", action_types)

    def test_handler_soft_fails_sample_insert_for_legacy_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_sample_insert_legacy",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll drop in a kick and snare loop.",
                            "actions": [
                                {
                                    "type": "sample_insert",
                                    "data": {
                                        "operation": "insert_sample",
                                        "items": [
                                            {
                                                "library_path": "Starter Kit v1/Processed Drums/Kick-01.mp3",
                                                "row_index": 0,
                                                "start_measure": 1,
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 90,
                    "output_tokens": 60,
                    "total_tokens": 150,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "add a kick",
                    "project_snapshot": "Track 1: empty",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "informational_response")
        self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")
        tool_defs = provider.request_body["tools"]
        daw_tool = next(
            tool for tool in tool_defs if tool.get("name") == "daw_assistant_actions"
        )
        action_types = self._tool_action_types(daw_tool)
        self.assertNotIn("project_edit", action_types)
        self.assertNotIn("sample_insert", action_types)

    def test_handler_preserves_sample_insert_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_sample_insert_capable",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll drop in a kick and snare loop.",
                            "actions": [
                                {
                                    "type": "sample_insert",
                                    "data": {
                                        "operation": "insert_sample",
                                        "items": [
                                            {
                                                "library_path": "Starter Kit v1/Processed Drums/Kick-01.mp3",
                                                "row_index": 0,
                                                "start_measure": 1,
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 90,
                    "output_tokens": 60,
                    "total_tokens": 150,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "add a kick",
                    "project_snapshot": "Track 1: empty",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.sample_insert.library"],
                    },
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "sample_insert")
        self.assertEqual(action["data"]["operation"], "insert_audio_clips")
        item = action["data"]["items"][0]
        self.assertEqual(
            item["library_path"],
            "Starter Kit v1/Processed Drums/Kick-01.mp3",
        )
        self.assertEqual(item["row_index"], 0)
        self.assertEqual(item["start_measure"], 1.0)
        tool_defs = provider.request_body["tools"]
        daw_tool = next(
            tool for tool in tool_defs if tool.get("name") == "daw_assistant_actions"
        )
        action_types = self._tool_action_types(daw_tool)
        self.assertIn("sample_insert", action_types)

    def test_handler_preserves_sample_replace_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_sample_replace_capable",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll swap that hit for a tighter one.",
                            "actions": [
                                {
                                    "type": "sample_insert",
                                    "data": {
                                        "operation": "replace_audio_clips",
                                        "items": [
                                            {
                                                "library_path": "Starter Kit v1/Processed Drums/Clap-01.mp3",
                                                "clip_index": 2,
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 90,
                    "output_tokens": 60,
                    "total_tokens": 150,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "swap this clap",
                    "project_snapshot": "Track 1: clap clip selected",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.sample_insert.library"],
                    },
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "sample_insert")
        self.assertEqual(action["data"]["operation"], "replace_audio_clips")
        item = action["data"]["items"][0]
        self.assertEqual(
            item["library_path"],
            "Starter Kit v1/Processed Drums/Clap-01.mp3",
        )
        self.assertEqual(item["clip_index"], 2)

    def test_handler_soft_fails_transpose_notes_for_legacy_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_transpose_legacy",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "I’ll raise the chords by an octave.",
                            "actions": [
                                {
                                    "type": "midi_compose",
                                    "data": {
                                        "operation": "octave_up",
                                        "target": {"prefer_selected": True},
                                        "octaves": 1,
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 75,
                    "output_tokens": 45,
                    "total_tokens": 120,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "octave up those chords",
                    "project_snapshot": "Track 1: MIDI Chords",
                    "selection_snapshot": "selected_clip_indices=0",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "informational_response")
        self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")

    def test_handler_normalizes_explicit_all_clips_scope_for_daw_actions(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Moved all clips to the beginning.",
                            "actions": [
                                {
                                    "type": "clip_edit",
                                    "data": {
                                        "operation": "move",
                                        "target": {
                                            "row_index": 0,
                                            "clip_index": 0,
                                        },
                                        "new_start_ms": 0,
                                    },
                                },
                                {
                                    "type": "clip_edit",
                                    "data": {
                                        "operation": "move",
                                        "target": {
                                            "row_index": 4,
                                            "clip_index": 3,
                                        },
                                        "new_start_ms": 0,
                                    },
                                },
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "move all clips to beginning",
                    "project_snapshot": "Track 1: vocal\nTrack 2: drums",
                    "selection_snapshot": "selected_clip_indices=0,3",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        arguments = output["arguments"]
        self.assertEqual(len(arguments["actions"]), 1)
        self.assertEqual(arguments["actions"][0]["data"]["target"], {"scope": "all"})

    def test_handler_soft_fails_bare_clip_edit_action(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_bare_clip_edit",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Moving the selected clip up one row.",
                            "actions": [
                                {
                                    "type": "clip_edit",
                                    "data": {},
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 160,
                    "output_tokens": 60,
                    "total_tokens": 220,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "move this selected clip up a row",
                    "project_snapshot": "Track 1: vocal\nTrack 2: drums",
                    "selection_snapshot": "selected_clip_indices=0",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "informational_response")
        self.assertEqual(
            output["arguments"]["message"],
            "I couldn't complete that request just now. Please try again.",
        )
        self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")
        self.assertTrue(payload["soft_error"]["usage_refunded"])

    def test_handler_normalizes_glue_clip_operation_alias(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_glue_clip",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Consolidating the selected clips.",
                            "actions": [
                                {
                                    "type": "clip_edit",
                                    "data": {
                                        "operation": "merge_clips",
                                        "target": {"prefer_selected": True},
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "merge the selected clips",
                    "project_snapshot": "Track 1: vocal",
                    "selection_snapshot": "selected_clip_indices=0,1",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "clip_edit")
        self.assertEqual(action["data"]["operation"], "glue")

    def test_handler_sanitizes_internal_leak_in_user_facing_message(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_internal_leak",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "informational_response",
                        "arguments": {
                            "message": "There is nothing in project snapshot because isEmpty = true.",
                            "cancels_pending": False,
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 80,
                    "output_tokens": 20,
                    "total_tokens": 100,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "one button mix",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "informational_response")
        self.assertEqual(
            output["arguments"]["message"],
            "I couldn't complete that request just now. Please try again.",
        )
        self.assertNotIn("soft_error", payload)

    def test_handler_shortens_tutorial_copy_and_repairs_fx_contains_target(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Here's how to adjust reverb on drums.",
                            "actions": [
                                {
                                    "type": "tutorial",
                                    "data": {
                                        "topic": "Adjust Reverb",
                                        "steps": [
                                            {
                                                "text": "Open the drums effects.",
                                                "target_id": "row:1:fx_index:reverb",
                                            }
                                        ],
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "show me where to adjust reverb on drums",
                    "project_snapshot": "Track 2: drums fx=[Reverb]",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "daw_assistant_actions")
        arguments = output["arguments"]
        self.assertEqual(arguments["assistant_message"], "Showing you in the UI.")
        self.assertEqual(
            arguments["actions"][0]["data"]["steps"][0]["target_id"],
            "row:1:fx_contains:reverb",
        )

    def test_handler_falls_back_to_clean_informational_response_on_invalid_tool_args(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": '{"mode":"execute","assistant_message":"Applied',
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Make the mix more modern.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "informational_response")
        self.assertEqual(
            output["arguments"]["message"],
            "I couldn't complete that request just now. Please try again.",
        )
        self.assertFalse(output["arguments"]["cancels_pending"])
        self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")
        self.assertTrue(payload["soft_error"]["usage_refunded"])
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.release_calls[0]["reserved_prompts"], 1)
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 0)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "soft_failed")
        self.assertEqual(
            self.fake_usage_repo.log_calls[-1]["error_code"],
            "invalid_structured_output",
        )
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["credits_charged"], 0)

    def test_handler_accepts_reset_fx_mix_actions_with_null_placeholder_intent(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "mode": "execute",
                            "assistant_message": "Removed all effects from the first track.",
                            "actions": [
                                {
                                    "goal": {
                                        "type": "mix_request",
                                        "intents": [
                                            {
                                                "kind": "null",
                                                "confidence": 1,
                                            }
                                        ],
                                        "target": {
                                            "scope": "row",
                                            "row_index": 0,
                                            "confidence": 1,
                                        },
                                        "intensity": 0,
                                        "reset_fx": True,
                                    }
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Take out all plugins on the first track.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "mix_model_request")
        self.assertNotIn("soft_error", payload)
        arguments = output["arguments"]
        self.assertEqual(arguments["assistant_message"], "Removed all effects from the first track.")
        goal = arguments["actions"][0]["goal"]
        self.assertTrue(goal["reset_fx"])
        self.assertEqual(goal["intents"][0]["kind"], "balance")
        self.assertEqual(goal["target"]["scope"], "row")
        self.assertEqual(goal["target"]["row_index"], 0)

    def test_handler_accepts_code_fenced_tool_arguments(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": """```json
{"mode":"execute","assistant_message":"Boosted the lead slightly.","actions":[{"goal":{"type":"mix_request","intents":[{"kind":"balance","direction":"up","descriptor":"slightly","confidence":1}],"target":{"scope":"row","row_index":0,"confidence":1},"intensity":0.2}}]}
```""",
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Turn the vocal up slightly.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        output = payload["output"][0]
        self.assertEqual(output["name"], "mix_model_request")
        self.assertEqual(output["arguments"]["mode"], "execute")
        self.assertEqual(
            output["arguments"]["actions"][0]["goal"]["target"]["row_index"],
            0,
        )
        self.assertNotIn("soft_error", payload)

    def test_handler_reports_refunded_soft_failures_to_observability(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": '{"mode":"execute","assistant_message":"Applied',
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Make the mix more modern.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                with mock.patch.object(api_responses, "capture_event") as capture_event_mock:
                    with mock.patch.object(
                        api_responses,
                        "capture_exception",
                    ) as capture_exception_mock:
                        result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        capture_event_mock.assert_any_call(
            "ai_response_soft_failed",
            distinct_id="user-123",
            properties=mock.ANY,
            enabled=True,
        )
        soft_failed_call = next(
            call
            for call in capture_event_mock.call_args_list
            if call.args and call.args[0] == "ai_response_soft_failed"
        )
        self.assertNotIn("prompt_text", soft_failed_call.kwargs["properties"])
        self.assertNotIn("prompt_preview", soft_failed_call.kwargs["properties"])
        self.assertEqual(
            soft_failed_call.kwargs["properties"]["prompt_length_chars"],
            len("Make the mix more modern."),
        )
        self.assertEqual(
            soft_failed_call.kwargs["properties"]["soft_error_code"],
            "invalid_structured_output",
        )
        self.assertFalse(
            any(
                call.kwargs.get("tags")
                == {
                    "service": "llm_proxy",
                    "error_type": "soft_failed_refunded",
                    "ai_feature": "ai_chat",
                }
                for call in capture_exception_mock.call_args_list
            )
        )

    def test_handler_refunds_usage_for_json_like_message_only_success(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "message",
                        "content": [
                            {
                                "type": "output_text",
                                "text": '{"assistant_message":"Applied"}',
                            }
                        ],
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Make the mix more modern.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload["output"][0]["name"], "informational_response")
        self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")
        self.assertTrue(payload["soft_error"]["usage_refunded"])
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 0)

    def test_handler_keeps_valid_function_call_even_if_message_output_is_present(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "message",
                        "content": [
                            {
                                "type": "output_text",
                                "text": "I can help with that.",
                            }
                        ],
                    },
                    {
                        "type": "function_call",
                        "name": "mix_model_request",
                        "arguments": {
                            "mode": "execute",
                            "assistant_message": "Increased the vocal level slightly.",
                            "actions": [
                                {
                                    "goal": {
                                        "type": "mix_request",
                                        "intents": [
                                            {
                                                "kind": "gain",
                                                "direction": "up",
                                                "confidence": 0.9,
                                            }
                                        ],
                                        "target": {
                                            "scope": "row",
                                            "row_index": 0,
                                            "confidence": 0.95,
                                        },
                                        "intensity": 0.3,
                                        "reset_fx": False,
                                    }
                                }
                            ],
                        },
                    },
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "Turn the vocals up a bit.",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload["output"][0]["name"], "mix_model_request")
        self.assertNotIn("soft_error", payload)
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 0)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "success")

    def test_handler_wraps_clean_message_only_success_without_refund(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_123",
                "model": "server-model",
                "output": [
                    {
                        "type": "message",
                        "content": [
                            {
                                "type": "output_text",
                                "text": "A compressor attack controls how quickly compression starts after a loud sound hits.",
                            }
                        ],
                    }
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 100,
                    "total_tokens": 300,
                },
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": "What does compressor attack do?",
                        }
                    ],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload["output"][0]["name"], "informational_response")
        self.assertEqual(
            payload["output"][0]["arguments"]["message"],
            "A compressor attack controls how quickly compression starts after a loud sound hits.",
        )
        self.assertNotIn("soft_error", payload)
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 0)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "success")

    def test_soft_failure_refund_boundary_matrix(self) -> None:
        cases = [
            {
                "name": "valid_mix_function_call",
                "response_body": {
                    "id": "resp_1",
                    "model": "server-model",
                    "output": [
                        {
                            "type": "function_call",
                            "name": "mix_model_request",
                            "arguments": {
                                "mode": "execute",
                                "assistant_message": "Raised vocals slightly.",
                                "actions": [
                                    {
                                        "goal": {
                                            "type": "mix_request",
                                            "intents": [
                                                {
                                                    "kind": "gain",
                                                    "direction": "up",
                                                    "confidence": 0.9,
                                                }
                                            ],
                                            "target": {
                                                "scope": "row",
                                                "row_index": 0,
                                                "confidence": 0.95,
                                            },
                                            "intensity": 0.3,
                                            "reset_fx": False,
                                        }
                                    }
                                ],
                            },
                        }
                    ],
                    "usage": {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20},
                },
                "prompt": "Turn the vocals up.",
                "should_refund": False,
            },
            {
                "name": "valid_message_only_text",
                "response_body": {
                    "id": "resp_2",
                    "model": "server-model",
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {
                                    "type": "output_text",
                                    "text": "Compression reduces dynamic range.",
                                }
                            ],
                        }
                    ],
                    "usage": {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20},
                },
                "prompt": "What does compression do?",
                "should_refund": False,
            },
            {
                "name": "valid_message_plus_function_call",
                "response_body": {
                    "id": "resp_3",
                    "model": "server-model",
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {"type": "output_text", "text": "I can do that."}
                            ],
                        },
                        {
                            "type": "function_call",
                            "name": "mix_model_request",
                            "arguments": {
                                "mode": "execute",
                                "assistant_message": "Lowered the pad slightly.",
                                "actions": [
                                    {
                                        "goal": {
                                            "type": "mix_request",
                                            "intents": [
                                                {
                                                    "kind": "gain",
                                                    "direction": "down",
                                                    "confidence": 0.9,
                                                }
                                            ],
                                            "target": {
                                                "scope": "row",
                                                "row_index": 4,
                                                "confidence": 0.95,
                                            },
                                            "intensity": 0.3,
                                            "reset_fx": False,
                                        }
                                    }
                                ],
                            },
                        },
                    ],
                    "usage": {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20},
                },
                "prompt": "Turn the pad down.",
                "should_refund": False,
            },
            {
                "name": "json_like_message_only",
                "response_body": {
                    "id": "resp_4",
                    "model": "server-model",
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {"type": "output_text", "text": '{"assistant_message":"Applied"}'}
                            ],
                        }
                    ],
                    "usage": {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20},
                },
                "prompt": "Make the mix more modern.",
                "should_refund": True,
            },
            {
                "name": "malformed_function_call_args",
                "response_body": {
                    "id": "resp_5",
                    "model": "server-model",
                    "output": [
                        {
                            "type": "function_call",
                            "name": "mix_model_request",
                            "arguments": '{"mode":"execute","assistant_message":"Applied',
                        }
                    ],
                    "usage": {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20},
                },
                "prompt": "Make the mix more modern.",
                "should_refund": True,
            },
            {
                "name": "missing_actions_function_call",
                "response_body": {
                    "id": "resp_6",
                    "model": "server-model",
                    "output": [
                        {
                            "type": "function_call",
                            "name": "mix_model_request",
                            "arguments": {
                                "mode": "execute",
                                "assistant_message": "Applied.",
                            },
                        }
                    ],
                    "usage": {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20},
                },
                "prompt": "Make the mix more modern.",
                "should_refund": True,
            },
        ]

        for case in cases:
            with self.subTest(case=case["name"]):
                self.fake_usage_repo.release_calls.clear()
                self.fake_usage_repo.finalize_calls.clear()
                self.fake_usage_repo.log_calls.clear()
                provider = _FakeProvider(response_body=case["response_body"])
                event = _authed_event(
                    json.dumps(
                        {
                            "input": [
                                {
                                    "role": "user",
                                    "content": case["prompt"],
                                }
                            ],
                        }
                    )
                )

                with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
                    with mock.patch.object(
                        api_responses,
                        "get_provider",
                        return_value=provider,
                    ):
                        result = api_responses.handler(event, None)

                self.assertEqual(result["statusCode"], 200)
                payload = json.loads(result["body"])
                if case["should_refund"]:
                    self.assertEqual(payload["soft_error"]["code"], "invalid_structured_output")
                    self.assertTrue(payload["soft_error"]["usage_refunded"])
                    self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
                    self.assertEqual(len(self.fake_usage_repo.finalize_calls), 0)
                else:
                    self.assertNotIn("soft_error", payload)
                    self.assertEqual(len(self.fake_usage_repo.release_calls), 0)
                    self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)

    def test_handler_releases_reserved_usage_when_upstream_raises(self) -> None:
        provider = _FakeProvider(forward_error=RuntimeError("boom"))
        event = _authed_event(
            json.dumps(
                {
                    "ai_feature": "assistant_chat",
                    "input": [{"role": "user", "content": "hello"}],
                }
            )
        )

        with mock.patch.object(api_responses, "_load_api_key", return_value="sk-test"):
            with mock.patch.object(api_responses, "get_provider", return_value=provider):
                result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 502)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.release_calls[0]["reserved_prompts"], 1)
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["status"], "failed")
        self.assertEqual(self.fake_usage_repo.log_calls[-1]["error_code"], "upstream_unavailable")

    def test_load_api_key_cache_refreshes_after_ttl(self) -> None:
        secret_client = mock.Mock()
        secret_client.get_secret_value.side_effect = [
            {"SecretString": "sk-old"},
            {"SecretString": "sk-new"},
        ]

        with mock.patch.dict(
            os.environ,
            {
                "LLM_API_KEY_SECRET_ARN": "arn:aws:secretsmanager:ap-northeast-2:123:secret:test",
                "LLM_SECRET_CACHE_TTL_SECONDS": "300",
            },
            clear=False,
        ):
            fake_boto3 = mock.Mock()
            fake_boto3.client.return_value = secret_client
            with mock.patch.object(api_responses, "boto3", fake_boto3):
                with mock.patch.object(
                    api_responses.time,
                    "time",
                    side_effect=[100.0, 200.0, 450.0],
                ):
                    first = api_responses._load_api_key()
                    second = api_responses._load_api_key()
                    third = api_responses._load_api_key()

        self.assertEqual(first, "sk-old")
        self.assertEqual(second, "sk-old")
        self.assertEqual(third, "sk-new")
        self.assertEqual(secret_client.get_secret_value.call_count, 2)

    def test_load_api_key_falls_back_to_openai_env_names(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "OPENAI_API_KEY": "sk-legacy",
            },
            clear=False,
        ):
            self.assertEqual(api_responses._load_api_key(), "sk-legacy")

    def test_load_api_key_prefers_ssm_parameter(self) -> None:
        ssm_client = mock.Mock()
        ssm_client.get_parameter.return_value = {
            "Parameter": {
                "Value": json.dumps({"OPENAI_API_KEY": "sk-parameter"}),
            },
        }

        with mock.patch.dict(
            os.environ,
            {
                "LLM_API_KEY_PARAMETER_NAME": "/mixroom/prod/llm",
                "LLM_API_KEY_SECRET_ARN": "arn:aws:secretsmanager:ap-northeast-2:123:secret:test",
            },
            clear=False,
        ):
            fake_boto3 = mock.Mock()
            fake_boto3.client.return_value = ssm_client
            with mock.patch.object(api_responses, "boto3", fake_boto3):
                self.assertEqual(api_responses._load_api_key("openai"), "sk-parameter")

        fake_boto3.client.assert_called_once_with("ssm")
        ssm_client.get_parameter.assert_called_once_with(
            Name="/mixroom/prod/llm",
            WithDecryption=True,
        )

    def test_load_api_key_accepts_provider_specific_secret_keys(self) -> None:
        secret_client = mock.Mock()
        secret_client.get_secret_value.return_value = {
            "SecretString": json.dumps({"ANTHROPIC_API_KEY": "sk-claude"}),
        }

        with mock.patch.dict(
            os.environ,
            {
                "LLM_API_KEY_SECRET_ARN": "arn:aws:secretsmanager:ap-northeast-2:123:secret:test",
            },
            clear=False,
        ):
            fake_boto3 = mock.Mock()
            fake_boto3.client.return_value = secret_client
            with mock.patch.object(api_responses, "boto3", fake_boto3):
                self.assertEqual(api_responses._load_api_key("claude"), "sk-claude")

    def test_load_api_key_prefers_active_provider_from_shared_secret(self) -> None:
        secret_client = mock.Mock()
        secret_client.get_secret_value.return_value = {
            "SecretString": json.dumps(
                {
                    "OPENAI_API_KEY": "sk-openai",
                    "ANTHROPIC_API_KEY": "sk-claude",
                    "GEMINI_API_KEY": "sk-gemini",
                }
            ),
        }

        with mock.patch.dict(
            os.environ,
            {
                "LLM_API_KEY_SECRET_ARN": "arn:aws:secretsmanager:ap-northeast-2:123:secret:test",
            },
            clear=False,
        ):
            fake_boto3 = mock.Mock()
            fake_boto3.client.return_value = secret_client
            with mock.patch.object(api_responses, "boto3", fake_boto3):
                self.assertEqual(api_responses._load_api_key("openai"), "sk-openai")
                self.assertEqual(api_responses._load_api_key("claude"), "sk-claude")
                self.assertEqual(api_responses._load_api_key("gemini"), "sk-gemini")


if __name__ == "__main__":
    unittest.main()
