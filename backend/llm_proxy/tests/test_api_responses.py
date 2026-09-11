from __future__ import annotations

import json
import copy
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
        observability: dict | None = None,
    ) -> None:
        self.name = name
        self.api_key: str | None = None
        self.request_body: dict | None = None
        self.timeout_seconds: int | None = None
        self._response_body = response_body or {"ok": True}
        self._status_code = status_code
        self._forward_error = forward_error
        self._observability = observability

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
        result = {
            "statusCode": self._status_code,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(self._response_body),
        }
        if self._observability is not None:
            result["observability"] = dict(self._observability)
        return result


class _SequencedFakeProvider:
    def __init__(self, responses: list[dict | Exception]) -> None:
        self.name = "fake-provider"
        self._responses = list(responses)
        self.request_bodies: list[dict] = []
        self.timeout_seconds: list[int] = []

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: dict,
        timeout_seconds: int,
    ) -> dict:
        self.request_bodies.append(json.loads(json.dumps(request_body)))
        self.timeout_seconds.append(timeout_seconds)
        index = len(self.request_bodies) - 1
        if index >= len(self._responses):
            raise AssertionError("Provider received more calls than expected.")
        response = self._responses[index]
        if isinstance(response, Exception):
            raise response
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(response),
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


class _LambdaContext:
    def __init__(self, remaining_ms: int) -> None:
        self.remaining_ms = remaining_ms

    def get_remaining_time_in_millis(self) -> int:
        return self.remaining_ms


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
    def _v3_context_body(self, **overrides):
        body = {
            "request_contract": "mixroom_v3_context_v2",
            "original_request": "Restart playback.",
            "conversation": [],
            "core_context": {
                "schema_version": "core_context_v3_prototype_1",
                "project": {"project_id": "secret-project", "bpm": 120},
            },
            "plan_schema_version": "plan_v3_prototype_2",
            "supported_command_types": ["transport.restart"],
            "resource_refs_enabled": True,
            "project_id": "secret-project",
            "prompt_trace_id": "trace-server-v3",
            "analytics_context": {
                "app_version": "3.0.0",
                "platform": "test",
                "ai_architecture": "v3",
            },
        }
        body.update(overrides)
        return body

    def _v3_respond_plan(self):
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "respond",
            "user_message": "No project changes were needed.",
            "commands": [],
            "question_options": [],
        }

    def _v3_provider_plan_payload(self, plan: dict, *, response_id: str) -> dict:
        return {
            "id": response_id,
            "output": [
                {
                    "type": "function_call",
                    "name": "submit_plan_v3",
                    "arguments": json.dumps(plan),
                }
            ],
            "usage": {"input_tokens": 20, "output_tokens": 10, "total_tokens": 30},
        }

    def test_v3_request_metrics_count_project_shape_without_content(self) -> None:
        metrics = api_responses._v3_request_metrics(
            client_body={"supported_command_types": ["one", "two", "three"]},
            server_request={
                "original_request": "PRIVATE_REQUEST_MARKER",
                "conversation": [{"role": "user", "content": "PRIVATE_TURN"}],
                "core_context": {
                    "rows": [{}, {}],
                    "clips": [{}, {}, {}],
                    "groups": [{}],
                    "library_assets": [{}, {}, {}, {}],
                    "private": "PRIVATE_CONTEXT_MARKER",
                },
                "supported_command_types": {"one", "two"},
            },
            provider_request={
                "instructions": "PRIVATE_INSTRUCTION_MARKER",
                "messages": [{"content": "PRIVATE_MESSAGE_MARKER"}],
                "tools": [
                    {
                        "parameters": {
                            "properties": {
                                "commands": {"items": {"anyOf": [{"type": "object"}]}}
                            }
                        }
                    }
                ],
            },
        )
        self.assertEqual(metrics["v3_row_count"], 2)
        self.assertEqual(metrics["v3_clip_count"], 3)
        self.assertEqual(metrics["v3_group_count"], 1)
        self.assertEqual(metrics["v3_library_asset_count"], 4)
        encoded = json.dumps(metrics, sort_keys=True)
        for marker in (
            "PRIVATE_REQUEST_MARKER",
            "PRIVATE_TURN",
            "PRIVATE_CONTEXT_MARKER",
            "PRIVATE_INSTRUCTION_MARKER",
            "PRIVATE_MESSAGE_MARKER",
        ):
            self.assertNotIn(marker, encoded)

    def _v3_midi_repair_body(self) -> dict:
        return self._v3_context_body(
            original_request="Rewrite the percussion and keep the mix balanced.",
            supported_command_types=["midi.replace_notes", "mix.apply_goal"],
            resource_refs_enabled=False,
            core_context={
                "schema_version": "core_context_v3_prototype_1",
                "project": {
                    "row_capacity": {
                        "current_rows": 1,
                        "max_rows": 5,
                        "can_create": True,
                    }
                },
                "rows": [
                    {
                        "row_id": 101,
                        "lane_kind": "instrument",
                        "instrument_id": "free-drums",
                        "mix_processing_supported": True,
                        "has_usable_signal": True,
                        "effects": [],
                    }
                ],
                "clips": [
                    {
                        "clip_id": "drum-clip",
                        "row_id": 101,
                        "kind": "midi",
                        "instrument_id": "free-drums",
                        "length_beats": 8,
                        "midi_notes": [],
                    }
                ],
                "groups": [],
                "library_assets": [],
                "instruments": ["free-drums"],
                "instrument_catalog": [
                    {
                        "instrument_id": "free-drums",
                        "name": "Free Drums",
                        "playable_pitch_ranges": [{"low": 35, "high": 81}],
                    }
                ],
                "effects": [],
            },
        )

    def _v3_midi_repair_plan(self, *, out_of_bounds: bool) -> dict:
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Rewrote the percussion and balanced it.",
            "commands": [
                {
                    "command_id": "replace-drums",
                    "type": "midi.replace_notes",
                    "arguments": {
                        "clip_id": "drum-clip",
                        "notes": [
                            {
                                "pitch": 38,
                                "start_beat": 7.5 if out_of_bounds else 7.0,
                                "length_beats": 1.0,
                                "velocity": 0.8,
                            }
                        ],
                    },
                },
                {
                    "command_id": "balance-drums",
                    "type": "mix.apply_goal",
                    "arguments": {
                        "target": {"scope": "row", "row_id": 101},
                        "intents": [
                            {
                                "kind": "gain",
                                "direction": "up",
                                "descriptor": None,
                            }
                        ],
                        "intensity": 0.5,
                        "execution_profile": "producer_safe",
                        "audibility": "noticeable",
                        "style_tags": [],
                        "reset_fx": False,
                        "reference": None,
                    },
                },
            ],
            "question_options": [],
        }

    def _v3_phone_cleanup_repair_body(self) -> dict:
        body = self._v3_midi_repair_body()
        body.update(
            {
                "original_request": "Clean up the vocal and make it clearer.",
                "supported_command_types": [
                    "row.apply_phone_mic_cleanup",
                    "mix.apply_goal",
                ],
            }
        )
        body["core_context"].update(
            {
                "rows": [
                    {
                        "row_id": 101,
                        "lane_kind": "audio",
                        "instrument_id": "",
                        "mix_processing_supported": True,
                        "has_usable_signal": True,
                        "effects": [],
                    }
                ],
                "clips": [
                    {
                        "clip_id": "vocal-clip",
                        "row_id": 101,
                        "kind": "audio",
                        "length_beats": 8,
                    }
                ],
                "instruments": [],
                "instrument_catalog": [],
                "effects": [{"effect_id": "Reverb", "parameters": []}],
            }
        )
        return body

    def _v3_phone_cleanup_repair_plan(self, *, conflicting: bool) -> dict:
        commands = [
            {
                "command_id": "cleanup-vocal",
                "type": "row.apply_phone_mic_cleanup",
                "arguments": {"row_id": 101},
            }
        ]
        if conflicting:
            commands.append(
                {
                    "command_id": "mix-vocal",
                    "type": "mix.apply_goal",
                    "arguments": {
                        "target": {"scope": "row", "row_id": 101},
                        "intents": [
                            {
                                "kind": "reverb",
                                "direction": "up",
                                "descriptor": None,
                            }
                        ],
                        "intensity": 0.4,
                        "execution_profile": "producer_safe",
                        "audibility": "noticeable",
                        "style_tags": [],
                        "reset_fx": False,
                        "reference": None,
                    },
                }
            )
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Cleaned up the vocal.",
            "commands": commands,
            "question_options": [],
        }

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

    def _tool_clip_edit_operations(self, daw_tool):
        actions = daw_tool["parameters"]["properties"]["actions"]
        items = actions["items"]
        for variant in items.get("oneOf", []):
            properties = variant.get("properties", {})
            type_schema = properties.get("type", {})
            type_values = set(type_schema.get("enum", []))
            if "const" in type_schema:
                type_values.add(type_schema["const"])
            if "clip_edit" not in type_values:
                continue
            return properties["data"]["properties"]["operation"]["enum"]
        return []

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

    def test_conversation_event_manual_mode_noops(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "event_type": "daw_execution_result",
                    "conversation_state_mode": "manual_history",
                    "project_id": "project-123",
                    "ai_feature": "ai_chat",
                    "conversation_session_id": "session-123",
                }
            ),
            path="/v1/llm/conversation-events",
        )

        result = api_responses.handler(event, None)
        payload = json.loads(result["body"])

        self.assertEqual(result["statusCode"], 200)
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["appended"])
        self.assertTrue(payload["noop"])

    def test_conversation_session_id_without_mode_stays_manual(self) -> None:
        self.assertEqual(
            api_responses._conversation_state_mode_from_body(
                {"conversation_session_id": "session-123"}
            ),
            "manual_history",
        )

    def test_conversation_runtime_fingerprint_uses_stable_contract_hash(self) -> None:
        base_request = {
            "model": "gpt-5.4-mini",
            "instructions": "PROJECT_SNAPSHOT\nTrack 1: Drums",
            "reasoning": {"effort": "minimal"},
            "prompt_cache_retention": "in_memory",
            "openai_conversation_contract_hash": "stable-contract",
        }
        changed_context_request = {
            **base_request,
            "instructions": "PROJECT_SNAPSHOT\nTrack 7: Bass",
        }

        first = api_responses._runtime_config_fingerprint(
            ai_feature="ai_chat",
            provider_name="openai",
            request_body=base_request,
            runtime_config={},
        )
        second = api_responses._runtime_config_fingerprint(
            ai_feature="ai_chat",
            provider_name="openai",
            request_body=changed_context_request,
            runtime_config={},
        )

        self.assertEqual(first, second)

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
            "mixroom-daw-v20260701a:ai_chat:4280ef7acfc3",
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

    def test_v3_endpoint_preserves_typed_planner_contract_and_forces_runtime(
        self,
    ) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp-v3",
                "model": "gpt-5.6-luna",
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(
                            {
                                "schema_version": "plan_v3_prototype_1",
                                "outcome": "respond",
                                "user_message": "No changes.",
                                "commands": [],
                                "question_options": [],
                            }
                        ),
                    }
                ],
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 20,
                    "total_tokens": 120,
                },
            }
        )
        request_body = {
            "model": "untrusted-client-model",
            "instructions": "V3 planner instructions",
            "input": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": "ORIGINAL_REQUEST_VERBATIM:\nDo nothing.",
                        }
                    ],
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "name": "submit_plan_v3",
                    "parameters": {"type": "object"},
                }
            ],
            "tool_choice": {"type": "function", "name": "submit_plan_v3"},
            "parallel_tool_calls": False,
            "max_output_tokens": 9999,
            "reasoning": {"effort": "high"},
            "store": True,
            "ai_feature": "ai_chat",
            "client_context": {"app_version": "3.0.0"},
        }
        event = _authed_event(
            json.dumps(request_body),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_ENABLED": "true",
                "AI_V3_MODEL": "gpt-5.6-luna",
                "AI_V3_REASONING_EFFORT": "low",
                "LLM_MODEL": "legacy-model",
            },
            clear=False,
        ), mock.patch.object(
            api_responses,
            "_load_api_key",
            return_value="sk-test",
        ), mock.patch.object(
            api_responses,
            "get_provider",
            return_value=provider,
        ):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        self.assertEqual(provider.request_body["model"], "gpt-5.6-luna")
        self.assertEqual(provider.request_body["reasoning"], {"effort": "low"})
        self.assertEqual(provider.request_body["max_output_tokens"], 8192)
        self.assertFalse(provider.request_body["parallel_tool_calls"])
        self.assertEqual(provider.request_body["prompt_cache_retention"], "24h")
        self.assertTrue(provider.request_body["store"])
        self.assertEqual(
            provider.request_body["tools"][0]["name"],
            "submit_plan_v3",
        )
        self.assertIsInstance(
            provider.request_body["messages"][0]["content"],
            list,
        )
        self.assertEqual(
            self.fake_usage_repo.reserve_calls[0]["reserved_prompts"],
            1,
        )
        self.assertEqual(
            self.fake_usage_repo.log_calls[-1]["feature"],
            "ai_chat_v3",
        )

    def test_v3_server_contract_builds_server_owned_request_and_sanitized_response(
        self,
    ) -> None:
        provider = _FakeProvider(
            observability={"provider_roundtrip_ms": 123, "secret": "internal"},
            response_body={
                "id": "secret-provider-response-id",
                "model": "secret-provider-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(self._v3_respond_plan()),
                    }
                ],
                "usage": {
                    "input_tokens": 50,
                    "input_tokens_details": {"cached_tokens": 0},
                    "output_tokens": 10,
                    "output_tokens_details": {"reasoning_tokens": 4},
                    "total_tokens": 60,
                },
                "reasoning": {"secret": "do-not-return"},
            }
        )
        body = self._v3_context_body(
            original_request="PRIVATE_ORIGINAL_MARKER",
            conversation=[
                {"role": "user", "content": "PRIVATE_CONVERSATION_MARKER"}
            ],
            core_context={
                "schema_version": "core_context_v3_prototype_1",
                "project": {
                    "project_id": "PRIVATE_PROJECT_MARKER",
                    "private_note": "PRIVATE_CONTEXT_MARKER",
                },
            },
            project_id="PRIVATE_PROJECT_MARKER",
            supported_command_types=["transport.restart", "client.evil_command"],
        )
        event = _authed_event(json.dumps(body), path="/v1/llm/v3/responses")

        output = StringIO()
        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_ENABLED": "true",
                "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "true",
                "AI_V3_MODEL": "gpt-5.6-luna",
                "AI_V3_REASONING_EFFORT": "low",
                "AI_V3_TIMEOUT_SECONDS": "60",
                "LLM_TIMEOUT_SECONDS": "60",
            },
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), redirect_stdout(output):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 200)
        assert provider.request_body is not None
        self.assertEqual(set(result), {"statusCode", "headers", "body"})
        self.assertEqual(provider.request_body["model"], "gpt-5.6-luna")
        self.assertEqual(provider.request_body["reasoning"], {"effort": "low"})
        self.assertEqual(provider.timeout_seconds, 27)
        self.assertEqual(provider.request_body["max_output_tokens"], 8192)
        self.assertFalse(provider.request_body["parallel_tool_calls"])
        self.assertEqual(provider.request_body["prompt_cache_retention"], "24h")
        self.assertTrue(provider.request_body["store"])
        self.assertIn("Mixroom's sole semantic and musical planner", provider.request_body["instructions"])
        variants = provider.request_body["tools"][0]["parameters"]["properties"]["commands"]["items"]["anyOf"]
        self.assertEqual(
            [variant["properties"]["type"]["enum"][0] for variant in variants],
            ["transport.restart"],
        )
        response = json.loads(result["body"])
        self.assertEqual(response["schema_version"], "v3_plan_response_server_v1")
        self.assertEqual(response["plan"], self._v3_respond_plan())
        self.assertEqual(response["trace"]["prompt_trace_id"], "trace-server-v3")
        self.assertIn("contract_fingerprint", response["trace"])
        rendered = json.dumps(response)
        for forbidden in (
            "secret-provider-model",
            "do-not-return",
            "reasoning_effort",
            "provider_response_id",
            "observability",
        ):
            self.assertNotIn(forbidden, rendered)
        logged = output.getvalue()
        log_lines = logged.strip().splitlines()
        final_log = json.loads(log_lines[-1])
        for line in log_lines[:-1]:
            for shape_metric in (
                "v3_row_count",
                "v3_clip_count",
                "v3_group_count",
                "v3_library_asset_count",
            ):
                self.assertNotIn(shape_metric, line)
        self.assertIn('"provider_timeout_seconds": 27', logged)
        self.assertIn('"provider_body_bytes":', logged)
        for key in (
            "v3_user_context_load_ms",
            "v3_context_validation_ms",
            "v3_provider_request_build_ms",
            "v3_usage_reservation_ms",
            "provider_roundtrip_ms",
            "v3_provider_validation_ms",
            "response_normalize_ms",
            "v3_usage_settlement_ms",
            "v3_original_request_bytes",
            "v3_conversation_bytes",
            "v3_core_context_bytes",
            "v3_instructions_bytes",
            "v3_messages_bytes",
            "v3_tool_schema_bytes",
            "v3_provider_request_bytes",
            "v3_conversation_turn_count",
            "v3_declared_command_type_count",
            "v3_effective_command_type_count",
            "v3_tool_command_variant_count",
            "v3_row_count",
            "v3_clip_count",
            "v3_group_count",
            "v3_library_asset_count",
            "v3_plan_command_count",
        ):
            self.assertIsInstance(final_log[key], int, key)
            self.assertGreaterEqual(final_log[key], 0, key)
        self.assertEqual(final_log["provider_roundtrip_ms"], 123)
        self.assertEqual(final_log["v3_conversation_turn_count"], 1)
        self.assertEqual(final_log["v3_declared_command_type_count"], 2)
        self.assertEqual(final_log["v3_effective_command_type_count"], 1)
        self.assertEqual(final_log["v3_tool_command_variant_count"], 1)
        self.assertEqual(final_log["v3_row_count"], 0)
        self.assertEqual(final_log["v3_clip_count"], 0)
        self.assertEqual(final_log["v3_group_count"], 0)
        self.assertEqual(final_log["v3_library_asset_count"], 0)
        self.assertEqual(final_log["v3_plan_command_count"], 0)
        self.assertTrue(final_log["usage_reported"])
        self.assertEqual(final_log["prompt_tokens"], 50)
        self.assertEqual(final_log["cached_prompt_tokens"], 0)
        self.assertFalse(final_log["prompt_cache_hit"])
        self.assertEqual(final_log["completion_tokens"], 10)
        self.assertEqual(final_log["reasoning_tokens"], 4)
        self.assertEqual(final_log["total_tokens"], 60)
        for forbidden in (
            "PRIVATE_ORIGINAL_MARKER",
            "PRIVATE_CONVERSATION_MARKER",
            "PRIVATE_PROJECT_MARKER",
            "PRIVATE_CONTEXT_MARKER",
            "secret-provider-model",
            "do-not-return",
            "No project changes were needed.",
        ):
            self.assertNotIn(forbidden, logged)

    def test_v3_detailed_usage_logging_handles_hits_missing_and_malformed_values(
        self,
    ) -> None:
        request_context = {}
        api_responses._update_request_log_context_with_cache_response(
            request_context,
            {
                "usage": {
                    "input_tokens": 100,
                    "input_tokens_details": {"cached_tokens": 80},
                    "output_tokens": 20,
                    "output_tokens_details": {"reasoning_tokens": 12},
                    "total_tokens": 120,
                }
            },
            include_detailed_usage=True,
        )
        self.assertEqual(request_context["cached_prompt_tokens"], 80)
        self.assertTrue(request_context["prompt_cache_hit"])
        self.assertEqual(request_context["reasoning_tokens"], 12)

        malformed_context = {}
        api_responses._update_request_log_context_with_cache_response(
            malformed_context,
            {
                "usage": {
                    "input_tokens": "invalid",
                    "input_tokens_details": {"cached_tokens": "invalid"},
                    "output_tokens": None,
                    "output_tokens_details": {"reasoning_tokens": []},
                    "total_tokens": {},
                }
            },
            include_detailed_usage=True,
        )
        self.assertEqual(malformed_context, {"usage_reported": False})

        missing_context = {}
        api_responses._update_request_log_context_with_cache_response(
            missing_context,
            {"usage": {"input_tokens": 1, "output_tokens": 1}},
            include_detailed_usage=True,
        )
        self.assertNotIn("cached_prompt_tokens", missing_context)
        self.assertNotIn("reasoning_tokens", missing_context)
        self.assertNotIn("total_tokens", missing_context)

    def test_v3_usage_measurements_preserve_only_reported_nonnegative_integers(self) -> None:
        for value in (None, "0", False, -1, 0.5, [], {}):
            with self.subTest(value=value):
                context = {}
                api_responses._update_request_log_context_with_cache_response(
                    context,
                    {"usage": {"input_tokens": value,
                               "input_tokens_details": {"cached_tokens": value},
                               "output_tokens_details": {"reasoning_tokens": value}}},
                    include_detailed_usage=True,
                )
                self.assertEqual(context, {"usage_reported": False})
        for usage in ({}, {"input_tokens_details": {}, "output_tokens_details": {}}):
            context = {}
            api_responses._update_request_log_context_with_cache_response(
                context, {"usage": usage}, include_detailed_usage=True,
            )
            self.assertEqual(context, {"usage_reported": False})
        context = {}
        api_responses._update_request_log_context_with_cache_response(
            context,
            {"usage": {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0,
                       "input_tokens_details": {"cached_tokens": 0},
                       "output_tokens_details": {"reasoning_tokens": 0}}},
            include_detailed_usage=True,
        )
        self.assertEqual(context, {
            "usage_reported": True, "prompt_tokens": 0, "completion_tokens": 0,
            "total_tokens": 0, "cached_prompt_tokens": 0,
            "reasoning_tokens": 0, "prompt_cache_hit": False,
        })

    def test_v3_context_rejection_logs_validation_time_before_finalization(self) -> None:
        body = self._v3_context_body()
        body["conversation"] = "invalid"
        output = StringIO()
        with mock.patch.dict(os.environ, {
            "AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true",
        }), redirect_stdout(output):
            result = api_responses.handler(_authed_event(
                json.dumps(body), path="/v1/llm/v3/responses",
            ), None)
        self.assertEqual(result["statusCode"], 400)
        final_log = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertGreaterEqual(final_log["v3_context_validation_ms"], 0)
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])

    def test_v3_provider_timeout_preserves_lambda_response_margin(self) -> None:
        provider = _FakeProvider(
            response_body={
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(self._v3_respond_plan()),
                    }
                ]
            }
        )
        event = _authed_event(
            json.dumps(self._v3_context_body()),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_ENABLED": "true",
                "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "true",
                "AI_V3_TIMEOUT_SECONDS": "20",
                "LLM_TIMEOUT_SECONDS": "60",
            },
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ):
            result = api_responses.handler(event, _LambdaContext(6_500))

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(provider.timeout_seconds, 4)

    def test_v3_exhausted_response_margin_skips_provider_and_releases_usage(
        self,
    ) -> None:
        provider = _FakeProvider(
            response_body={
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(self._v3_respond_plan()),
                    }
                ]
            }
        )
        event = _authed_event(
            json.dumps(self._v3_context_body()),
            path="/v1/llm/v3/responses",
        )
        output = StringIO()

        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_ENABLED": "true",
                "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "true",
                "AI_V3_TIMEOUT_SECONDS": "20",
            },
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), redirect_stdout(output):
            self.assertEqual(
                api_responses._v3_request_timeout_seconds(_LambdaContext(2_999)),
                0,
            )
            self.assertEqual(
                api_responses._v3_request_timeout_seconds(_LambdaContext(3_000)),
                1,
            )
            result = api_responses.handler(event, _LambdaContext(2_999))

        self.assertEqual(result["statusCode"], 504)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_upstream_timeout",
        )
        self.assertIsNone(provider.request_body)
        self.assertEqual(len(self.fake_usage_repo.reserve_calls), 1)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(
            self.fake_usage_repo.log_calls[-1]["error_code"],
            "upstream_timeout",
        )
        logged = output.getvalue()
        final_log = json.loads(logged.strip().splitlines()[-1])
        self.assertIn('"message": "V3 provider deadline exhausted"', logged)
        self.assertIn('"failure_stage": "provider_deadline"', logged)
        self.assertNotIn('"message": "Forwarding LLM request"', logged)
        for key in (
            "v3_provider_request_bytes",
            "v3_provider_request_build_ms",
            "v3_usage_reservation_ms",
            "provider_roundtrip_ms",
            "v3_usage_settlement_ms",
        ):
            self.assertIn(key, final_log)

    def test_v3_upstream_timeout_returns_controlled_gateway_timeout(self) -> None:
        provider = _FakeProvider(forward_error=TimeoutError("timed out"))
        event = _authed_event(
            json.dumps(self._v3_context_body()),
            path="/v1/llm/v3/responses",
        )
        output = StringIO()

        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_ENABLED": "true",
                "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "true",
            },
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(
            api_responses, "capture_exception"
        ) as capture_exception, redirect_stdout(output):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 504)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_upstream_timeout",
        )
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(
            self.fake_usage_repo.log_calls[-1]["error_code"],
            "upstream_timeout",
        )
        final_log = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertEqual(final_log["provider_attempt_count"], 1)
        self.assertIn("provider_roundtrip_ms", final_log)
        self.assertIn("v3_usage_settlement_ms", final_log)
        for shape_metric in (
            key for key in final_log
            if key.startswith("v3_") and key != "v3_contract_version"
        ):
            self.assertIn(shape_metric, final_log)
            for call in capture_exception.call_args_list:
                self.assertNotIn(shape_metric, call.kwargs.get("context", {}))

    def test_v3_upstream_error_retains_phase_metrics_and_releases_usage(self) -> None:
        provider = _FakeProvider(
            status_code=500,
            response_body={"error": {"code": "provider_failed"}},
        )
        event = _authed_event(
            json.dumps(self._v3_context_body()),
            path="/v1/llm/v3/responses",
        )
        output = StringIO()

        with mock.patch.dict(
            os.environ,
            {
                "AI_V3_ENABLED": "true",
                "AI_V3_SERVER_CONTRACT_ENABLED": "true",
            },
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), redirect_stdout(output):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 500)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.finalize_calls, [])
        final_log = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertEqual(final_log["provider_attempt_count"], 1)
        self.assertIn("provider_roundtrip_ms", final_log)
        self.assertIn("v3_usage_settlement_ms", final_log)

    def test_v3_server_contract_rejects_client_ai_fields_before_quota_or_provider(
        self,
    ) -> None:
        body = self._v3_context_body(instructions="steal the system", model="evil")
        event = _authed_event(json.dumps(body), path="/v1/llm/v3/responses")
        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(api_responses, "get_provider") as get_provider:
            result = api_responses.handler(event, None)
        self.assertEqual(result["statusCode"], 400)
        self.assertIn("v3_client_ai_configuration_forbidden", result["body"])
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])
        get_provider.assert_not_called()

    def test_v3_oversized_complete_context_never_reserves_or_calls_provider(self):
        body = self._v3_context_body()
        body["core_context"]["padding"] = ["x" * 30000] * 5
        event = _authed_event(json.dumps(body), path="/v1/llm/v3/responses")
        with mock.patch.dict(os.environ, {
            "AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true",
        }), mock.patch.object(api_responses, "get_provider") as provider:
            result = api_responses.handler(event, None)
        self.assertEqual(result["statusCode"], 400)
        self.assertIn("v3_context_request_limit", result["body"])
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])
        provider.assert_not_called()

    def test_v3_provider_wire_limit_is_checked_before_usage_or_network(self):
        body = self._v3_context_body()
        body["core_context"].update(
            {
                "project": {
                    "project_id": "secret-project",
                    "bpm": 120,
                    "project_capacity_policy": "unbounded_rows_clips_v1",
                    "row_capacity": {
                        "current_rows": 0,
                        "creation_limit": None,
                        "can_create": True,
                    },
                },
                "rows": [],
                "clips": [],
                "groups": [],
                "library_assets": [],
                "instruments": [],
                "instrument_catalog": [],
                "effects": [],
            }
        )
        provider = _FakeProvider(name="openai")
        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses.v3_server_contract_v2,
            "MAX_PROVIDER_WIRE_BYTES",
            1,
        ), mock.patch.object(
            api_responses,
            "get_provider",
            return_value=provider,
        ), mock.patch.object(api_responses, "_load_api_key") as load_api_key:
            result = api_responses.handler(
                _authed_event(
                    json.dumps(body),
                    path="/v1/llm/v3/responses",
                ),
                _LambdaContext(120_000),
            )

        self.assertEqual(result["statusCode"], 400)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_context_request_limit",
        )
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])
        self.assertIsNone(provider.request_body)
        load_api_key.assert_not_called()

    def test_v3_server_contract_rejects_malformed_clip_row_before_quota_or_provider(
        self,
    ) -> None:
        body = self._v3_context_body()
        body["core_context"].update(
            {
                "rows": [
                    {
                        "row_id": 101,
                        "lane_kind": "audio",
                        "instrument_id": "",
                        "mix_processing_supported": True,
                        "has_usable_signal": True,
                        "effects": [],
                    }
                ],
                "clips": [
                    {
                        "clip_id": "clip-1",
                        "row_id": [],
                        "kind": "audio",
                    }
                ],
            }
        )
        event = _authed_event(json.dumps(body), path="/v1/llm/v3/responses")

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(api_responses, "get_provider") as get_provider:
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_capability_context_invalid",
        )
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])
        get_provider.assert_not_called()

    def test_v3_provider_build_rejections_return_logged_errors_before_usage(self) -> None:
        contract = api_responses.v3_server_contract_v2
        empty_surface = self._v3_context_body(
            supported_command_types=["clip.delete"],
            resource_refs_enabled=False,
        )
        oversized_schema = self._v3_context_body(
            supported_command_types=sorted(contract.SERVER_COMMAND_TYPES),
        )
        # Legal identifiers and collection sizes whose repeated schema enums
        # exceed the runtime-tool limit, not the incoming request limit.
        oversized_schema["core_context"].update(
            rows=[
                {"row_id": i + 1, "lane_kind": "audio", "mix_processing_supported": True}
                for i in range(32)
            ],
            clips=[
                {"clip_id": f"{i:03d}" + "x" * 125, "row_id": i % 32 + 1, "kind": "audio"}
                for i in range(128)
            ],
            library_assets=[
                {"asset_id": f"{i:03d}" + "y" * 125} for i in range(250)
            ],
        )
        for body, code in (
            (empty_surface, "v3_command_surface_empty"),
            (oversized_schema, "v3_capability_context_limit"),
        ):
            with self.subTest(code=code):
                raw_body = json.dumps(body)
                contract.validate_context_request(
                    body, raw_body_bytes=len(raw_body.encode("utf-8"))
                )
                provider = mock.Mock(name="provider")
                provider.name = "fake-provider"
                output = StringIO()
                with mock.patch.dict(
                    os.environ,
                    {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
                ), mock.patch.object(
                    api_responses, "get_provider", return_value=provider
                ), mock.patch.object(
                    api_responses, "get_ai_feature_runtime", return_value={}
                ), mock.patch.object(
                    api_responses, "_load_api_key"
                ) as load_api_key, redirect_stdout(output):
                    result = api_responses.handler(
                        _authed_event(raw_body, path="/v1/llm/v3/responses"),
                        _LambdaContext(30_000),
                    )

                self.assertEqual(result["statusCode"], 400)
                self.assertEqual(json.loads(result["body"])["error"]["code"], code)
                provider.forward_request.assert_not_called()
                load_api_key.assert_not_called()
                self.assertEqual(self.fake_usage_repo.reserve_calls, [])
                self.assertEqual(self.fake_usage_repo.release_calls, [])
                self.assertEqual(self.fake_usage_repo.finalize_calls, [])
                self.assertEqual(self.fake_usage_repo.log_calls, [])
                logs = output.getvalue().strip().splitlines()
                self.assertEqual(len(logs), 1)
                final_log = json.loads(logs[0])
                self.assertEqual(final_log["status_code"], 400)
                self.assertEqual(final_log["error"], code)
                self.assertIsInstance(final_log["v3_provider_request_build_ms"], int)
                self.assertGreaterEqual(final_log["v3_provider_request_build_ms"], 0)
                self.assertNotIn("secret-project", output.getvalue())

    def test_v3_server_contract_rejects_unknown_fields_and_versions_before_quota(
        self,
    ) -> None:
        cases = [
            self._v3_context_body(unknown="value"),
            self._v3_context_body(plan_schema_version="plan_v99"),
            self._v3_context_body(original_request="x" * 8001),
        ]
        for body in cases:
            with self.subTest(body_keys=sorted(body)):
                event = _authed_event(json.dumps(body), path="/v1/llm/v3/responses")
                with mock.patch.dict(
                    os.environ,
                    {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
                    clear=False,
                ):
                    result = api_responses.handler(event, None)
                self.assertIn(result["statusCode"], {400, 413})
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])

    def test_v3_server_contract_kill_switches_run_before_provider(self) -> None:
        server_event = _authed_event(
            json.dumps(self._v3_context_body()), path="/v1/llm/v3/responses"
        )
        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "false"},
            clear=False,
        ), mock.patch.object(api_responses, "get_provider") as get_provider:
            result = api_responses.handler(server_event, None)
        self.assertEqual(result["statusCode"], 503)
        self.assertIn("v3_server_contract_disabled", result["body"])
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])
        get_provider.assert_not_called()

    def test_v3_server_contract_sanitizes_invalid_provider_output(self) -> None:
        invalid_payloads = [
            {"output": []},
            {
                "output": [
                    {"type": "function_call", "name": "submit_plan_v3", "arguments": "{"},
                ]
            },
            {
                "output": [
                    {"type": "function_call", "name": "submit_plan_v3", "arguments": json.dumps(self._v3_respond_plan())},
                    {"type": "function_call", "name": "submit_plan_v3", "arguments": json.dumps(self._v3_respond_plan())},
                ]
            },
            {
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(
                            {
                                **self._v3_respond_plan(),
                                "outcome": "plan",
                                "commands": [
                                    {
                                        "command_id": "evil-1",
                                        "type": "project.set_tempo",
                                        "arguments": {
                                            "bpm": 120,
                                            "time_stretch_audio": False,
                                            "preserve_pitch": True,
                                        },
                                    }
                                ],
                            }
                        ),
                    }
                ]
            },
        ]
        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                provider = _FakeProvider(response_body=payload)
                output = StringIO()
                event = _authed_event(
                    json.dumps(self._v3_context_body()),
                    path="/v1/llm/v3/responses",
                )
                with mock.patch.dict(
                    os.environ,
                    {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
                    clear=False,
                ), mock.patch.object(
                    api_responses, "_load_api_key", return_value="sk-test"
                ), mock.patch.object(
                    api_responses, "get_provider", return_value=provider
                ), redirect_stdout(output):
                    result = api_responses.handler(event, None)
                self.assertEqual(result["statusCode"], 502)
                response = json.loads(result["body"])
                self.assertEqual(response["error"]["code"], "v3_invalid_provider_output")
                self.assertEqual(set(response), {"error"})
                final_log = json.loads(output.getvalue().strip().splitlines()[-1])
                self.assertEqual(final_log["provider_attempt_count"], 1)
                self.assertIn("v3_provider_validation_ms", final_log)
                self.assertIn("v3_usage_settlement_ms", final_log)

    def test_v3_precision_extension_uses_one_provider_attempt(self):
        body = self._v3_midi_repair_body()
        body['core_context']['project'].update(bpm=108, midi_boundary_policy='extend_1ms_v1')
        body['core_context']['clips'][0]['length_beats'] = 31.9986
        plan = self._v3_midi_repair_plan(out_of_bounds=False)
        plan['commands'][0]['arguments']['notes'][0]['start_beat'] = 31
        provider = _SequencedFakeProvider([
            self._v3_provider_plan_payload(plan, response_id='precision-response')])
        output = StringIO()
        with mock.patch.dict(os.environ, {
            'AI_V3_ENABLED': 'true', 'AI_V3_SERVER_CONTRACT_ENABLED': 'true'}, clear=False), \
            mock.patch.object(api_responses, '_load_api_key', return_value='sk-test'), \
            mock.patch.object(api_responses, 'get_provider', return_value=provider), \
            redirect_stdout(output):
            result = api_responses.handler(_authed_event(json.dumps(body),
                path='/v1/llm/v3/responses'), _LambdaContext(30000))
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(json.loads(result['body'])['plan'], plan)
        self.assertEqual(len(provider.request_bodies), 1)
        final_log = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertEqual(final_log['provider_attempt_count'], 1)
        self.assertFalse(final_log.get('semantic_repair_attempted', False))
        self.assertEqual(self.fake_usage_repo.release_calls, [])
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)

    def test_512_note_handler_budgets_and_settlement(self):
        for marker, count, ceiling, status in (
            (None, 256, 8192, 200), (None, 257, 8192, 502),
            ('notes_512_v1', 512, 16384, 200), ('notes_512_v1', 513, 16384, 502),
        ):
            with self.subTest(marker=marker, count=count):
                self.fake_usage_repo.release_calls.clear()
                self.fake_usage_repo.finalize_calls.clear()
                body = self._v3_midi_repair_body()
                if marker:
                    body['core_context']['project']['generated_midi_policy'] = marker
                plan = self._v3_midi_repair_plan(out_of_bounds=False)
                plan['commands'] = [plan['commands'][0]]
                plan['commands'][0]['arguments']['notes'] = [
                    {'pitch': 60, 'start_beat': 0, 'length_beats': 0.5, 'velocity': 0.8}
                    for _ in range(count)]
                provider = _SequencedFakeProvider([
                    self._v3_provider_plan_payload(plan, response_id='budget-fixture')])
                with mock.patch.dict(os.environ, {'AI_V3_ENABLED': 'true',
                    'AI_V3_SERVER_CONTRACT_ENABLED': 'true',
                    'LLM_MAX_OUTPUT_TOKENS': '16384'}), \
                    mock.patch.object(api_responses, '_load_api_key', return_value='test'), \
                    mock.patch.object(api_responses, 'get_provider', return_value=provider), \
                    redirect_stdout(StringIO()):
                    result = api_responses.handler(_authed_event(json.dumps(body),
                        path='/v1/llm/v3/responses'), _LambdaContext(60000))
                self.assertEqual(result['statusCode'], status)
                self.assertEqual(len(provider.request_bodies), 1)
                self.assertEqual(provider.request_bodies[0]['max_output_tokens'], ceiling)
                self.assertEqual(len(self.fake_usage_repo.finalize_calls), int(status == 200))
                self.assertEqual(len(self.fake_usage_repo.release_calls), int(status != 200))

    def test_pitch_repair_details_are_precise_and_not_public(self):
        body = self._v3_midi_repair_body()
        body['core_context']['instrument_catalog'][0]['playable_pitch_ranges'] = [{'low': 40, 'high': 86}]
        invalid = self._v3_midi_repair_plan(out_of_bounds=False)
        invalid['commands'][0]['arguments']['notes'][0]['pitch'] = 36
        corrected = copy.deepcopy(invalid)
        corrected['commands'][0]['arguments']['notes'][0]['pitch'] = 40
        provider = _SequencedFakeProvider([
            self._v3_provider_plan_payload(invalid, response_id='invalid'),
            self._v3_provider_plan_payload(corrected, response_id='corrected')])
        output = StringIO()
        with mock.patch.dict(os.environ, {'AI_V3_ENABLED': 'true',
                'AI_V3_SERVER_CONTRACT_ENABLED': 'true'}, clear=False), \
                mock.patch.object(api_responses, '_load_api_key', return_value='test'), \
                mock.patch.object(api_responses, 'get_provider', return_value=provider), \
                redirect_stdout(output):
            result = api_responses.handler(_authed_event(json.dumps(body),
                path='/v1/llm/v3/responses'), _LambdaContext(60000))
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(json.loads(result['body'])['plan'], corrected)
        correction_text = provider.request_bodies[1]['messages'][0]['content'][-1]['text']
        self.assertIn('"command_index":0', correction_text)
        self.assertIn('"command_type":"midi.replace_notes"', correction_text)
        self.assertIn('"effective_instrument_id":"free-drums"', correction_text)
        self.assertIn('"rejected_pitches":[36]', correction_text)
        self.assertIn('"playable_pitch_ranges":[{"high":86,"low":40}]', correction_text)
        for field in ('validation_details', 'rejected_pitches', 'effective_instrument_id'):
            self.assertNotIn(field, result['body'])
            self.assertNotIn(field, output.getvalue())
        self.assertEqual(self.fake_usage_repo.release_calls, [])
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)

    def test_512_note_full_repair_keeps_budget_and_single_attempt_allowance(self):
        for repaired in (True, False):
            with self.subTest(repaired=repaired):
                self.fake_usage_repo.release_calls.clear()
                self.fake_usage_repo.finalize_calls.clear()
                body = self._v3_midi_repair_body()
                body['core_context']['project']['generated_midi_policy'] = 'notes_512_v1'
                valid = self._v3_midi_repair_plan(out_of_bounds=False)
                valid['commands'] = [valid['commands'][0]]
                valid['commands'][0]['arguments']['notes'] = [
                    {'pitch': 60, 'start_beat': 0, 'length_beats': 0.5, 'velocity': 0.8}
                    for _ in range(512)]
                invalid = copy.deepcopy(valid)
                invalid['commands'][0]['arguments']['notes'][0]['pitch'] = 34
                provider = _SequencedFakeProvider([
                    self._v3_provider_plan_payload(invalid, response_id='first'),
                    self._v3_provider_plan_payload(valid if repaired else invalid, response_id='second')])
                with mock.patch.dict(os.environ, {'AI_V3_ENABLED': 'true',
                    'AI_V3_SERVER_CONTRACT_ENABLED': 'true', 'LLM_MAX_OUTPUT_TOKENS': ''}), \
                    mock.patch.object(api_responses, '_load_api_key', return_value='test'), \
                    mock.patch.object(api_responses, 'get_provider', return_value=provider), \
                    redirect_stdout(StringIO()):
                    result = api_responses.handler(_authed_event(json.dumps(body),
                        path='/v1/llm/v3/responses'), _LambdaContext(60000))
                self.assertEqual(result['statusCode'], 200 if repaired else 502)
                self.assertEqual(len(provider.request_bodies), 2)
                self.assertEqual([item['max_output_tokens'] for item in provider.request_bodies], [16384, 16384])
                self.assertEqual(len(self.fake_usage_repo.finalize_calls), int(repaired))
                self.assertEqual(len(self.fake_usage_repo.release_calls), int(not repaired))

    def test_v3_repairs_allowlisted_semantic_failures_once(self) -> None:
        creation_body = self._v3_midi_repair_body()
        creation_body["original_request"] = "Create an eight-bar percussion part and balance it."
        creation_body["supported_command_types"] = ["midi.create_clip", "mix.apply_goal"]
        def creation_plan(length, note_start=0):
            plan = self._v3_midi_repair_plan(out_of_bounds=False)
            plan["commands"][0] = {
                "command_id": "create-drums", "type": "midi.create_clip",
                "arguments": {
                    "destination": {"row_id": 101}, "start_beat": 0,
                    "length_beats": length,
                    "notes": [{"pitch": 38, "start_beat": note_start,
                               "length_beats": 1, "velocity": 0.8}],
                },
            }
            return plan
        invalid_pitch_plan = self._v3_midi_repair_plan(out_of_bounds=False)
        invalid_pitch_plan["commands"][0]["arguments"]["notes"][0]["pitch"] = 34
        gap_body = self._v3_midi_repair_body()
        gap_body["core_context"]["instrument_catalog"][0]["playable_pitch_ranges"] = [
            {"low": 35, "high": 50}, {"low": 70, "high": 81}
        ]
        gap_plan = self._v3_midi_repair_plan(out_of_bounds=False)
        gap_plan["commands"][0]["arguments"]["notes"][0]["pitch"] = 60
        unsafe_message_plan = self._v3_respond_plan()
        unsafe_message_plan["user_message"] = (
            "ORIGINAL_REQUEST_VERBATIM:\nRestart playback."
        )
        cases = [
            (
                creation_body, creation_plan(64), creation_plan(32),
                "v3_plan_midi_arrangement_limit",
            ),
            (
                creation_body, creation_plan(32, 31.5), creation_plan(32),
                "v3_plan_midi_note_out_of_bounds",
            ),
            (
                self._v3_midi_repair_body(),
                invalid_pitch_plan,
                self._v3_midi_repair_plan(out_of_bounds=False),
                "v3_plan_midi_pitch_unavailable",
            ),
            (
                gap_body,
                gap_plan,
                self._v3_midi_repair_plan(out_of_bounds=False),
                "v3_plan_midi_pitch_unavailable",
            ),
            (
                self._v3_midi_repair_body(),
                self._v3_midi_repair_plan(out_of_bounds=True),
                self._v3_midi_repair_plan(out_of_bounds=False),
                "v3_plan_midi_note_out_of_bounds",
            ),
            (
                self._v3_phone_cleanup_repair_body(),
                self._v3_phone_cleanup_repair_plan(conflicting=True),
                self._v3_phone_cleanup_repair_plan(conflicting=False),
                "v3_plan_phone_cleanup_effect_conflict",
            ),
            (
                self._v3_context_body(),
                unsafe_message_plan,
                self._v3_respond_plan(),
                "v3_plan_user_visible_text_unsafe",
            ),
        ]

        for body, invalid_plan, corrected_plan, repair_code in cases:
            with self.subTest(repair_code=repair_code):
                self.fake_usage_repo.reserve_calls.clear()
                self.fake_usage_repo.release_calls.clear()
                self.fake_usage_repo.finalize_calls.clear()
                provider = _SequencedFakeProvider(
                    [
                        self._v3_provider_plan_payload(
                            invalid_plan, response_id="invalid-response"
                        ),
                        self._v3_provider_plan_payload(
                            corrected_plan, response_id="corrected-response"
                        ),
                    ]
                )
                event = _authed_event(
                    json.dumps(body), path="/v1/llm/v3/responses"
                )
                output = StringIO()

                with mock.patch.dict(
                    os.environ,
                    {
                        "AI_V3_ENABLED": "true",
                        "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                        "AI_V3_TIMEOUT_SECONDS": "27",
                    },
                    clear=False,
                ), mock.patch.object(
                    api_responses, "_load_api_key", return_value="sk-test"
                ), mock.patch.object(
                    api_responses, "get_provider", return_value=provider
                ), mock.patch.object(
                    api_responses.time,
                    "monotonic",
                    side_effect=[100.0, 105.2],
                ), redirect_stdout(output):
                    result = api_responses.handler(event, _LambdaContext(30_000))

                self.assertEqual(result["statusCode"], 200)
                response = json.loads(result["body"])
                self.assertEqual(response["plan"], corrected_plan)
                self.assertEqual(len(provider.request_bodies), 2)
                self.assertEqual(provider.timeout_seconds, [27, 21])
                first_request, repair_request = provider.request_bodies
                self.assertEqual(first_request["tools"], repair_request["tools"])
                repair_tools = json.dumps(repair_request["tools"])
                for paid_effect_id in ("Distortion", "De-Esser", "Clipper"):
                    self.assertNotIn(paid_effect_id, repair_tools)
                self.assertEqual(
                    first_request["tool_choice"], repair_request["tool_choice"]
                )
                self.assertEqual(first_request["model"], repair_request["model"])
                self.assertEqual(first_request["metadata"], repair_request["metadata"])
                first_content = first_request["messages"][0]["content"]
                repair_content = repair_request["messages"][0]["content"]
                self.assertEqual(repair_content[:-1], first_content)
                repair_without_correction = json.loads(json.dumps(repair_request))
                repair_without_correction["messages"][0]["content"].pop()
                self.assertEqual(repair_without_correction, first_request)
                self.assertIn("SEMANTIC_REPAIR_REQUIRED", repair_content[-1]["text"])
                self.assertIn(repair_code, repair_content[-1]["text"])
                self.assertNotIn("invalid-response", json.dumps(repair_request))
                self.assertNotIn(
                    json.dumps(invalid_plan, sort_keys=True),
                    json.dumps(repair_request, sort_keys=True),
                )
                self.assertEqual(len(self.fake_usage_repo.reserve_calls), 1)
                self.assertEqual(self.fake_usage_repo.release_calls, [])
                self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)
                final_log = json.loads(output.getvalue().strip().splitlines()[-1])
                self.assertEqual(final_log["provider_attempt_count"], 2)
                self.assertEqual(
                    final_log["semantic_repair_error_code"], repair_code
                )
                self.assertTrue(final_log["semantic_repair_succeeded"])
                self.assertIn("v3_provider_validation_ms", final_log)
                self.assertIn("v3_usage_settlement_ms", final_log)

    def test_v3_arrangement_repair_stops_or_clarifies_safely(self) -> None:
        body = self._v3_midi_repair_body()
        body["original_request"] = "Create a 16-bar percussion part."
        body["supported_command_types"] = ["midi.create_clip"]
        invalid_plan = self._v3_respond_plan()
        invalid_plan["outcome"] = "plan"
        invalid_plan["commands"] = [{
            "command_id": "create-drums", "type": "midi.create_clip",
            "arguments": {
                "destination": {"row_id": 101}, "start_beat": 0, "length_beats": 64,
                "notes": [{"pitch": 38, "start_beat": 0, "length_beats": 1, "velocity": 0.8}],
            },
        }]
        clarification = self._v3_respond_plan()
        clarification.update(outcome="clarify", user_message="Would an eight-bar section work instead?", question_options=[])
        for followup, deadline, status, attempts in (
            (invalid_plan, 101.0, 502, 2),
            (clarification, 101.0, 200, 2),
            (invalid_plan, 127.1, 502, 1),
            (TimeoutError("repair timeout"), 101.0, 504, 2),
        ):
            with self.subTest(status=status, attempts=attempts):
                self.fake_usage_repo.reserve_calls.clear()
                self.fake_usage_repo.release_calls.clear()
                self.fake_usage_repo.finalize_calls.clear()
                provider = _SequencedFakeProvider([
                    self._v3_provider_plan_payload(invalid_plan, response_id="invalid-creation"),
                    followup if isinstance(followup, Exception) else self._v3_provider_plan_payload(followup, response_id="corrected-creation"),
                ])
                with mock.patch.dict(os.environ, {
                    "AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                    "AI_V3_TIMEOUT_SECONDS": "27",
                }, clear=False), mock.patch.object(
                    api_responses, "_load_api_key", return_value="sk-test"
                ), mock.patch.object(
                    api_responses, "get_provider", return_value=provider
                ), mock.patch.object(
                    api_responses.time, "monotonic", side_effect=[100.0, deadline]
                ), redirect_stdout(StringIO()):
                    result = api_responses.handler(
                        _authed_event(json.dumps(body), path="/v1/llm/v3/responses"),
                        _LambdaContext(30_000),
                    )
                self.assertEqual(result["statusCode"], status)
                self.assertEqual(len(provider.request_bodies), attempts)
                self.assertEqual(len(self.fake_usage_repo.reserve_calls), 1)
                self.assertEqual(len(self.fake_usage_repo.release_calls), int(status != 200))
                self.assertEqual(len(self.fake_usage_repo.finalize_calls), int(status == 200))
                if status == 200:
                    self.assertEqual(json.loads(result["body"])["plan"], clarification)
                else:
                    self.assertEqual(set(json.loads(result["body"])), {"error"})

    def test_v3_pitch_repair_is_bounded_and_settles_once(self) -> None:
        valid_plan = self._v3_midi_repair_plan(out_of_bounds=False)
        invalid_plan = self._v3_midi_repair_plan(out_of_bounds=False)
        invalid_plan["commands"][0]["arguments"]["notes"][0]["pitch"] = 82
        cases = [
            ("valid", [valid_plan], [100.0], 200, 1, True),
            ("still_invalid", [invalid_plan, invalid_plan], [100.0, 101.0], 502, 2, False),
            ("deadline_exhausted", [invalid_plan], [100.0, 127.1], 502, 1, False),
            ("repair_timeout", [invalid_plan, TimeoutError("repair timed out")], [100.0, 101.0], 504, 2, False),
        ]
        for name, plans, clock_values, status, attempts, finalized in cases:
            with self.subTest(name=name):
                self.fake_usage_repo.reserve_calls.clear()
                self.fake_usage_repo.release_calls.clear()
                self.fake_usage_repo.finalize_calls.clear()
                provider = _SequencedFakeProvider([
                    plan if isinstance(plan, Exception) else self._v3_provider_plan_payload(
                        plan, response_id=f"synthetic-{index}"
                    )
                    for index, plan in enumerate(plans)
                ])
                event = _authed_event(
                    json.dumps(self._v3_midi_repair_body()), path="/v1/llm/v3/responses"
                )
                output = StringIO()
                with mock.patch.dict(os.environ, {
                    "AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                    "AI_V3_TIMEOUT_SECONDS": "27",
                }, clear=False), mock.patch.object(
                    api_responses, "_load_api_key", return_value="sk-test"
                ), mock.patch.object(
                    api_responses, "get_provider", return_value=provider
                ), mock.patch.object(
                    api_responses.time, "monotonic", side_effect=clock_values
                ), redirect_stdout(output):
                    result = api_responses.handler(event, _LambdaContext(30_000))
                self.assertEqual(result["statusCode"], status)
                self.assertEqual(len(provider.request_bodies), attempts)
                self.assertEqual(len(self.fake_usage_repo.reserve_calls), 1)
                self.assertEqual(len(self.fake_usage_repo.finalize_calls), int(finalized))
                self.assertEqual(len(self.fake_usage_repo.release_calls), int(not finalized))
                if not finalized:
                    self.assertEqual(set(json.loads(result["body"])), {"error"})
                if attempts == 2:
                    self.assertEqual(provider.timeout_seconds, [27, 26])

    def test_v3_second_unsafe_message_stops_and_releases_once(self) -> None:
        unsafe_plan = self._v3_respond_plan()
        unsafe_plan["user_message"] = (
            "ORIGINAL_REQUEST_VERBATIM:\nRestart playback."
        )
        provider = _SequencedFakeProvider(
            [
                self._v3_provider_plan_payload(
                    unsafe_plan, response_id="unsafe-response-1"
                ),
                self._v3_provider_plan_payload(
                    unsafe_plan, response_id="unsafe-response-2"
                ),
            ]
        )
        event = _authed_event(
            json.dumps(self._v3_context_body()),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(
            api_responses.time, "monotonic", side_effect=[100.0, 101.0]
        ):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 502)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_invalid_provider_output",
        )
        self.assertEqual(len(provider.request_bodies), 2)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.finalize_calls, [])

    def test_v3_valid_plan_does_not_request_semantic_repair(self) -> None:
        provider = _SequencedFakeProvider(
            [
                self._v3_provider_plan_payload(
                    self._v3_respond_plan(), response_id="valid-response"
                )
            ]
        )
        event = _authed_event(
            json.dumps(self._v3_context_body()), path="/v1/llm/v3/responses"
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(api_responses.time, "monotonic", return_value=100.0):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(len(provider.request_bodies), 1)
        self.assertNotIn("SEMANTIC_REPAIR_REQUIRED", json.dumps(provider.request_bodies))
        self.assertEqual(len(self.fake_usage_repo.finalize_calls), 1)

    def test_v3_non_allowlisted_provider_failure_is_not_retried(self) -> None:
        provider = _SequencedFakeProvider([{"output": []}])
        event = _authed_event(
            json.dumps(self._v3_context_body()), path="/v1/llm/v3/responses"
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(api_responses.time, "monotonic", return_value=100.0):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 502)
        self.assertEqual(len(provider.request_bodies), 1)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.finalize_calls, [])

    def test_v3_second_invalid_semantic_plan_stops_and_releases_once(self) -> None:
        invalid_plan = self._v3_midi_repair_plan(out_of_bounds=True)
        provider = _SequencedFakeProvider(
            [
                self._v3_provider_plan_payload(
                    invalid_plan, response_id="invalid-response-1"
                ),
                self._v3_provider_plan_payload(
                    invalid_plan, response_id="invalid-response-2"
                ),
            ]
        )
        event = _authed_event(
            json.dumps(self._v3_midi_repair_body()),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(
            api_responses.time, "monotonic", side_effect=[100.0, 101.0]
        ):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 502)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_invalid_provider_output",
        )
        self.assertEqual(len(provider.request_bodies), 2)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.finalize_calls, [])

    def test_v3_exhausted_shared_deadline_skips_semantic_repair(self) -> None:
        invalid_plan = self._v3_midi_repair_plan(out_of_bounds=True)
        provider = _SequencedFakeProvider(
            [
                self._v3_provider_plan_payload(
                    invalid_plan, response_id="invalid-response"
                )
            ]
        )
        event = _authed_event(
            json.dumps(self._v3_midi_repair_body()),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(
            api_responses.time, "monotonic", side_effect=[100.0, 127.1]
        ):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 502)
        self.assertEqual(len(provider.request_bodies), 1)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)

    def test_v3_semantic_repair_timeout_preserves_timeout_response(self) -> None:
        invalid_plan = self._v3_midi_repair_plan(out_of_bounds=True)
        provider = _SequencedFakeProvider(
            [
                self._v3_provider_plan_payload(
                    invalid_plan, response_id="invalid-response"
                ),
                TimeoutError("repair timed out"),
            ]
        )
        event = _authed_event(
            json.dumps(self._v3_midi_repair_body()),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), mock.patch.object(
            api_responses.time, "monotonic", side_effect=[100.0, 101.0]
        ):
            result = api_responses.handler(event, _LambdaContext(30_000))

        self.assertEqual(result["statusCode"], 504)
        self.assertEqual(
            json.loads(result["body"])["error"]["code"],
            "v3_upstream_timeout",
        )
        self.assertEqual(len(provider.request_bodies), 2)
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.finalize_calls, [])

    def test_v3_server_contract_rejects_unadvertised_effect_parameter_privately(self) -> None:
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Updated the guitar.",
            "commands": [
                {
                    "command_id": "effect-1",
                    "type": "effect.ensure_configured",
                    "arguments": {
                        "row_id": 101,
                        "effect_id": "Distortion",
                        "parameters": [{"parameter_id": "hpf", "value": 0.5}],
                    },
                }
            ],
            "question_options": [],
        }
        provider = _FakeProvider(
            response_body={
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": json.dumps(plan),
                    }
                ]
            }
        )
        body = self._v3_context_body(
            original_request="Make the guitar richer.",
            supported_command_types=["effect.ensure_configured", "mix.apply_goal"],
            resource_refs_enabled=False,
            core_context={
                "schema_version": "core_context_v3_prototype_1",
                "project": {
                    "row_capacity": {
                        "current_rows": 1,
                        "max_rows": 5,
                        "can_create": True,
                    }
                },
                "rows": [
                    {
                        "row_id": 101,
                        "lane_kind": "instrument",
                        "instrument_id": "free-piano",
                        "mix_processing_supported": True,
                        "has_usable_signal": False,
                        "effects": [],
                    }
                ],
                "clips": [],
                "groups": [],
                "library_assets": [],
                "instruments": ["free-piano"],
                "instrument_catalog": [
                    {
                        "instrument_id": "free-piano",
                        "name": "Free Piano",
                        "playable_pitch_ranges": [{"low": 40, "high": 84}],
                    }
                ],
                "effects": [
                    {
                        "effect_id": "Distortion",
                        "parameters": [
                            {"parameter_id": "HPF Frequency", "range": [0, 1]}
                        ],
                    }
                ],
            },
        )
        event = _authed_event(json.dumps(body), path="/v1/llm/v3/responses")
        output = StringIO()
        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true", "AI_V3_SERVER_CONTRACT_ENABLED": "true"},
            clear=False,
        ), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(
            api_responses, "get_provider", return_value=provider
        ), redirect_stdout(output):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 502)
        response = json.loads(result["body"])
        self.assertEqual(response["error"]["code"], "v3_invalid_provider_output")
        self.assertEqual(set(response), {"error"})
        self.assertNotIn("hpf", result["body"].lower())
        self.assertNotIn("distortion", result["body"].lower())
        self.assertNotIn("hpf", output.getvalue().lower())
        self.assertNotIn("distortion", output.getvalue().lower())
        self.assertEqual(len(self.fake_usage_repo.release_calls), 1)
        self.assertEqual(self.fake_usage_repo.finalize_calls, [])
        assert provider.request_body is not None
        runtime_tool = json.dumps(provider.request_body["tools"][0])
        self.assertIn("HPF Frequency", runtime_tool)
        self.assertNotIn('"hpf"', runtime_tool)

    def test_v3_endpoint_kill_switch_blocks_before_provider_usage(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "input": [{"role": "user", "content": "test"}],
                    "tools": [
                        {
                            "type": "function",
                            "name": "submit_plan_v3",
                            "parameters": {"type": "object"},
                        }
                    ],
                    "tool_choice": {
                        "type": "function",
                        "name": "submit_plan_v3",
                    },
                    "parallel_tool_calls": False,
                    "store": True,
                }
            ),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "false"},
            clear=False,
        ):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 503)
        self.assertIn("v3_disabled", result["body"])
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])

    def test_v3_endpoint_rejects_legacy_or_arbitrary_tool_shapes(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "Mute drums.",
                    "tools": [{"type": "function", "name": "other_tool"}],
                }
            ),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true"},
            clear=False,
        ):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("OpenAI-compatible planner request", result["body"])
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])

    def test_v3_endpoint_rejects_non_function_submit_tool(self) -> None:
        event = _authed_event(
            json.dumps(
                {
                    "input": [{"role": "user", "content": "test"}],
                    "tools": [
                        {
                            "type": "custom",
                            "name": "submit_plan_v3",
                            "parameters": {"type": "object"},
                        }
                    ],
                    "tool_choice": {
                        "type": "function",
                        "name": "submit_plan_v3",
                    },
                    "parallel_tool_calls": False,
                    "store": True,
                }
            ),
            path="/v1/llm/v3/responses",
        )

        with mock.patch.dict(
            os.environ,
            {"AI_V3_ENABLED": "true"},
            clear=False,
        ):
            result = api_responses.handler(event, None)

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("submit_plan_v3 tool", result["body"])
        self.assertEqual(self.fake_usage_repo.reserve_calls, [])

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
            "mixroom-daw-v20260701a:ai_chat:c49fea7425fa",
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
            "mixroom-daw-v20260701a:ai_chat:4280ef7acfc3",
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
        self.assertEqual(reserve_call["daily_prompt_limit"], 100)
        self.assertEqual(reserve_call["weekly_prompt_limit"], 400)
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

    def test_handler_soft_fails_pitch_shift_for_legacy_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_pitch_legacy",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Lowering the instrumental one key.",
                            "actions": [
                                {
                                    "type": "clip_edit",
                                    "data": {
                                        "operation": "pitch_shift",
                                        "target": {"prefer_selected": True},
                                        "delta_semitones": -1,
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
                    "user_text": "lower the background one key",
                    "project_snapshot": "Track 1: instrumental",
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
        daw_tool = next(
            tool
            for tool in provider.request_body["tools"]
            if tool.get("name") == "daw_assistant_actions"
        )
        self.assertNotIn("pitch_shift", self._tool_clip_edit_operations(daw_tool))

    def test_handler_preserves_pitch_shift_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_pitch_capable",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Lowering the instrumental one key.",
                            "actions": [
                                {
                                    "type": "clip_edit",
                                    "data": {
                                        "operation": "pitch_shift",
                                        "target": {"prefer_selected": True},
                                        "semitones": "-1",
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
                    "user_text": "lower the background one key",
                    "project_snapshot": "Track 1: instrumental",
                    "selection_snapshot": "selected_clip_indices=0",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.clip_edit.pitch_shift"],
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
        self.assertEqual(action["type"], "clip_edit")
        self.assertEqual(action["data"]["operation"], "pitch_shift")
        self.assertEqual(action["data"]["delta_semitones"], -1.0)
        daw_tool = next(
            tool
            for tool in provider.request_body["tools"]
            if tool.get("name") == "daw_assistant_actions"
        )
        self.assertIn("pitch_shift", self._tool_clip_edit_operations(daw_tool))

    def test_handler_repairs_pitch_shift_effect_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_pitch_effect_repair",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Pitching the instrumental down.",
                            "actions": [
                                {
                                    "type": "effect_edit",
                                    "data": {
                                        "operation": "add",
                                        "effect_name": "Pitch Shift",
                                        "target": {},
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
                    "user_text": "lower the background music by 1 key",
                    "project_snapshot": "Track 3: instrumental",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.clip_edit.pitch_shift"],
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
        self.assertEqual(action["type"], "clip_edit")
        self.assertEqual(action["data"]["operation"], "pitch_shift")
        self.assertEqual(action["data"]["delta_semitones"], -1.0)
        self.assertEqual(action["data"]["target"]["label_contains"], "Instrumental")

    def test_handler_repairs_pitch_automation_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_pitch_automation_repair",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Pulling the pitch down.",
                            "actions": [
                                {
                                    "type": "automation_edit",
                                    "data": {
                                        "operation": "set_points",
                                        "param_name": "Pitch",
                                        "target": {},
                                        "points": [
                                            {"time_ms": 0, "value": -1},
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
                    "user_text": "lower the background music by 1 key",
                    "project_snapshot": "Track 3: instrumental",
                    "selection_snapshot": "",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.clip_edit.pitch_shift"],
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
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "clip_edit")
        self.assertEqual(action["data"]["operation"], "pitch_shift")
        self.assertEqual(action["data"]["delta_semitones"], -1.0)

    def test_handler_fallbacks_capability_question_when_model_output_invalid(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_capability_fallback",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "",
                            "actions": [],
                        },
                    }
                ],
                "usage": {"input_tokens": 40, "output_tokens": 10, "total_tokens": 50},
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "무슨 작업을 해줄수있어",
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
        self.assertIn("MIDI", output["arguments"]["message"])
        self.assertNotIn("soft_error", payload)

    def test_handler_fallbacks_basic_midi_creation_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_midi_fallback",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "",
                            "actions": [],
                        },
                    }
                ],
                "usage": {"input_tokens": 40, "output_tokens": 10, "total_tokens": 50},
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "미디 클립 만들기",
                    "project_snapshot": "Track 1: empty",
                    "selection_snapshot": "selected_row=0",
                    "ai_feature": "assistant_chat",
                    "client_context": {
                        "ai_capabilities": ["daw.midi_compose.instrument_insert"],
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
        self.assertEqual(action["type"], "midi_compose")
        self.assertEqual(action["data"]["operation"], "create_clip")
        self.assertGreater(len(action["data"]["notes"]), 0)
        self.assertNotIn("soft_error", payload)

    def test_handler_fallbacks_hihat_sample_insert_for_capable_clients(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_hihat_fallback",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "",
                            "actions": [],
                        },
                    }
                ],
                "usage": {"input_tokens": 40, "output_tokens": 10, "total_tokens": 50},
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "add some dope hihats",
                    "project_snapshot": "Track 1: Piano (instrument)",
                    "selection_snapshot": "selected_row=0",
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
        self.assertEqual(item["library_path"], "role:hat")
        self.assertEqual(item["target"]["prefer_selected"], False)
        self.assertNotIn("soft_error", payload)

    def test_handler_does_not_fallback_existing_kick_edits_to_sample_insert(self) -> None:
        prompts = [
            "make the kicks on track 1 louder",
            "do not add clips. make kicks on track 1 louder",
            "turn up the kick volume on the selected row",
            "drop the kick volume",
            "make the kick hit harder",
        ]
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                provider = _FakeProvider(
                    response_body={
                        "id": "resp_no_sample_insert_fallback",
                        "model": "server-model",
                        "output": [
                            {
                                "type": "function_call",
                                "name": "daw_assistant_actions",
                                "arguments": {
                                    "assistant_message": "",
                                    "actions": [],
                                },
                            }
                        ],
                        "usage": {
                            "input_tokens": 40,
                            "output_tokens": 10,
                            "total_tokens": 50,
                        },
                    }
                )
                event = _authed_event(
                    json.dumps(
                        {
                            "conversation": [],
                            "user_text": prompt,
                            "project_snapshot": "Track 1: Kick loop",
                            "selection_snapshot": "selected_row=0",
                            "ai_feature": "assistant_chat",
                            "client_context": {
                                "ai_capabilities": [
                                    "daw.sample_insert.library",
                                    "daw.row_mix",
                                ],
                            },
                        }
                    )
                )

                with mock.patch.object(
                    api_responses, "_load_api_key", return_value="sk-test"
                ):
                    with mock.patch.object(
                        api_responses, "get_provider", return_value=provider
                    ):
                        result = api_responses.handler(event, None)

                self.assertEqual(result["statusCode"], 200)
                payload = json.loads(result["body"])
                output = payload["output"][0]
                self.assertEqual(output["name"], "informational_response")
                self.assertIn("soft_error", payload)

    def test_handler_fallbacks_glue_selected_clips_when_model_output_invalid(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_glue_fallback",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "",
                            "actions": [],
                        },
                    }
                ],
                "usage": {"input_tokens": 40, "output_tokens": 10, "total_tokens": 50},
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "combine the selected clips into one sample",
                    "project_snapshot": "Track 1: drums",
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
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "clip_edit")
        self.assertEqual(action["data"]["operation"], "glue")
        self.assertEqual(action["data"]["target"]["scope"], "selected")
        self.assertNotIn("soft_error", payload)

    def test_handler_clarifies_glue_request_without_selected_clips(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_glue_clarify",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "",
                            "actions": [],
                        },
                    }
                ],
                "usage": {"input_tokens": 40, "output_tokens": 10, "total_tokens": 50},
            }
        )
        event = _authed_event(
            json.dumps(
                {
                    "conversation": [],
                    "user_text": "combine the drums to one sample",
                    "project_snapshot": "Track 1: Kick\nTrack 2: Snare",
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
        action = output["arguments"]["actions"][0]
        self.assertEqual(action["type"], "clarify")
        self.assertIn("Which clips", action["data"]["question"])
        self.assertNotIn("soft_error", payload)

    def test_handler_preserves_existing_daw_actions(self) -> None:
        provider = _FakeProvider(
            response_body={
                "id": "resp_existing_actions",
                "model": "server-model",
                "output": [
                    {
                        "type": "function_call",
                        "name": "daw_assistant_actions",
                        "arguments": {
                            "assistant_message": "Updated the project.",
                            "actions": [
                                {
                                    "type": "audio_enhance",
                                    "data": {
                                        "operation": "cleanup",
                                        "target": {"prefer_selected": True},
                                    },
                                },
                                {
                                    "type": "row_group_edit",
                                    "data": {
                                        "operation": "group_rows",
                                        "row_indices": [0, 1],
                                        "name": "Vocals",
                                    },
                                },
                                {
                                    "type": "row_color_edit",
                                    "data": {
                                        "operation": "delete",
                                        "target": {"row_index": 1},
                                    },
                                },
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
                    "user_text": "clean this recording and group the vocals",
                    "project_snapshot": "Track 1: voice\nTrack 2: harmony",
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
        actions = output["arguments"]["actions"]
        self.assertEqual([action["type"] for action in actions], [
            "audio_enhance",
            "row_group_edit",
            "row_color_edit",
        ])
        self.assertEqual(actions[0]["data"]["operation"], "phone_mic_cleanup")
        self.assertEqual(actions[1]["data"]["operation"], "create")
        self.assertEqual(actions[2]["data"]["operation"], "clear")

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
