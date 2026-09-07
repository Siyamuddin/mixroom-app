from __future__ import annotations

import copy
import hashlib
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
from common import v3_server_contract  # noqa: E402
from common import v3_server_contract_v1  # noqa: E402
from handlers import api_responses  # noqa: E402


FIXTURE = Path(__file__).with_name("fixtures") / "v3_context_v1_released_client.json"
V1_MODULE = SRC / "common" / "v3_server_contract_v1.py"
V1_MODULE_SHA256 = "aee1617745d34421417a358f15c1e2d18384bfe274e60dcde352ef81c102ae60"
V1_ASSETS = SRC / "common" / "v3_contract_assets_v1"
V1_ASSET_SHA256 = {
    "v3_contract_metadata.json": "5675e9adbf19cdbbf87cd1229adaf80d5228744202683f9fe391faf47a766fc8",
    "v3_instructions.txt": "e5be3fc19a013ca4a5e5fa3b0e9a55fd7711136530b8e5dac4e9eecea4d5e327",
    "v3_instructions_resource_refs.txt": "2758f7938f575672c7ad09ac7c405793e6e38de83f47ad61541b10cda0cdb506",
    "v3_submit_plan_tool.json": "618f7ae8d98a6c4aa5b8816492f5296dfbac52d943a557aa1669970db6162c42",
    "v3_submit_plan_tool_resource_refs.json": "4598d32a7846cb5caa04557f4a2597aca0febe7a1751649b507add79b638ffd1",
}


def _released_v1_request() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def _released_v1_request_matrix() -> dict[str, dict]:
    minimal = _released_v1_request()

    free_preserved_state = copy.deepcopy(minimal)
    free_preserved_state.update(
        {
            "original_request": (
                "Bypass the existing distortion, then give the project a concert-hall feel."
            ),
            "conversation": [
                {"role": "user", "content": "Keep the current arrangement."},
                {"role": "assistant", "content": "I will preserve the arrangement."},
            ],
            "supported_command_types": [
                "effect.set_bypassed",
                "mix.apply_goal",
                "transport.restart",
            ],
            "project_id": "released-free-project",
            "prompt_trace_id": "released-free-trace",
            "analytics_context": {
                "app_version": "1.0.0",
                "platform": "windows",
                "ai_architecture": "v3",
                "subscription_plan": "free",
            },
        }
    )
    free_preserved_state["core_context"] = {
        "schema_version": "core_context_v3_prototype_1",
        "profile": "essential",
        "state_digest": "released-free-preserved-state",
        "request_mode": "new_request",
        "project": {
            "project_id": "released-free-project",
            "bpm": 120,
            "beats_per_bar": 4,
            "beat_unit": 4,
            "row_capacity": {
                "current_rows": 6,
                "max_rows": 5,
                "can_create": False,
            },
        },
        "transport": {"playing": False, "recording": False},
        "selection": {"selected_row_ids": [11], "selected_clip_ids": ["clip-11"]},
        "rows": [
            {
                "row_id": row_id,
                "name": f"Track {row_id}",
                "lane_kind": "audio",
                "mix_processing_supported": row_id <= 13,
                "clip_ids": [f"clip-{row_id}"] if row_id <= 13 else [],
                "effects": (
                    [
                        {
                            "effect_instance_id": "paid-distortion-11",
                            "effect_id": "Distortion",
                            "bypassed": False,
                        }
                    ]
                    if row_id == 11
                    else []
                ),
            }
            for row_id in range(11, 17)
        ],
        "groups": [],
        "master": {"gain_db": 0, "pan_signed": 0, "effects": []},
        "clips": [
            {
                "clip_id": f"clip-{row_id}",
                "row_id": row_id,
                "kind": "audio",
                "start_beat": 0,
                "length_beats": 8,
            }
            for row_id in range(11, 14)
        ],
        "instruments": [],
        "instrument_catalog": [],
        "effects": [{"effect_id": "Reverb"}],
        "library_assets": [],
        "capabilities": free_preserved_state["supported_command_types"],
        "runtime_capabilities": ["daw.row_mix"],
    }

    paid_resource_refs = copy.deepcopy(minimal)
    paid_resource_refs.update(
        {
            "original_request": (
                "Create orchestral drums, write eight bars, and balance them with Guitar."
            ),
            "conversation": [
                {"role": "user", "content": "Make the guitar progression faster."},
                {"role": "assistant", "content": "The guitar progression is now faster."},
            ],
            "supported_command_types": [
                "midi.create_clip",
                "midi.replace_notes",
                "mix.apply_goal",
                "row.create",
                "row.set_instrument",
                "transport.restart",
            ],
            "resource_refs_enabled": True,
            "project_id": "released-paid-project",
            "prompt_trace_id": "released-paid-trace",
            "analytics_context": {
                "app_version": "1.0.0",
                "platform": "macos",
                "ai_architecture": "v3",
                "subscription_plan": "producer",
            },
        }
    )
    paid_resource_refs["core_context"] = {
        "schema_version": "core_context_v3_prototype_1",
        "profile": "essential",
        "state_digest": "released-paid-resource-refs",
        "request_mode": "new_request",
        "project": {
            "project_id": "released-paid-project",
            "bpm": 138,
            "beats_per_bar": 4,
            "beat_unit": 4,
            "row_capacity": {
                "current_rows": 10,
                "max_rows": 32,
                "can_create": True,
            },
        },
        "transport": {"playing": False, "recording": False},
        "selection": {"selected_row_ids": [21], "selected_clip_ids": ["guitar-clip"]},
        "rows": [
            {
                "row_id": 21,
                "name": "Guitar",
                "lane_kind": "audio",
                "mix_processing_supported": True,
                "clip_ids": ["guitar-clip"],
                "effects": [],
            },
            {
                "row_id": 22,
                "name": "Rock Drums",
                "lane_kind": "instrument",
                "instrument_id": "Acoustic Drum Kit",
                "mix_processing_supported": True,
                "clip_ids": ["drum-midi"],
                "effects": [],
            },
        ],
        "groups": [
            {"group_id": "rhythm", "name": "Rhythm", "member_row_ids": [21, 22]}
        ],
        "master": {"gain_db": 0, "pan_signed": 0, "effects": []},
        "clips": [
            {
                "clip_id": "guitar-clip",
                "row_id": 21,
                "kind": "audio",
                "start_beat": 0,
                "length_beats": 32,
            },
            {
                "clip_id": "drum-midi",
                "row_id": 22,
                "kind": "midi",
                "start_beat": 0,
                "length_beats": 32,
                "notes": [
                    {"pitch": 36, "start_beat": 0, "duration_beats": 1, "velocity": 100},
                    {"pitch": 38, "start_beat": 1, "duration_beats": 1, "velocity": 96},
                ],
            },
        ],
        "instruments": ["Acoustic Drum Kit", "Orchestral Percussion"],
        "instrument_catalog": [
            {
                "instrument_id": "Acoustic Drum Kit",
                "name": "Acoustic Drum Kit",
                "playable_pitch_ranges": [{"low": 35, "high": 81}],
            },
            {
                "instrument_id": "Orchestral Percussion",
                "name": "Orchestral Percussion",
                "playable_pitch_ranges": [{"low": 35, "high": 81}],
            },
        ],
        "effects": [
            {"effect_id": "Reverb"},
            {"effect_id": "Distortion"},
            {"effect_id": "Compressor"},
            {"effect_id": "EQ 3-Band"},
        ],
        "library_assets": [
            {"asset_id": "sample:kick", "path": "Starter Kit/Kick.wav", "role": "kick"},
            {"asset_id": "sample:snare", "path": "Starter Kit/Snare.wav", "role": "snare"},
        ],
        "capabilities": paid_resource_refs["supported_command_types"],
        "runtime_capabilities": ["daw.midi_compose.instrument_insert", "daw.row_mix"],
    }

    return {
        "minimal": minimal,
        "free_preserved_state": free_preserved_state,
        "paid_resource_refs": paid_resource_refs,
    }


def _plan() -> dict:
    return {
        "schema_version": "plan_v3_prototype_2",
        "outcome": "plan",
        "user_message": "Restarting playback.",
        "commands": [
            {
                "command_id": "restart",
                "type": "transport.restart",
                "arguments": {},
            }
        ],
        "question_options": [],
    }


def _provider_payload() -> dict:
    return {
        "id": "provider-response",
        "output": [
            {
                "type": "function_call",
                "name": "submit_plan_v3",
                "arguments": json.dumps(_plan()),
            }
        ],
        "usage": {"input_tokens": 20, "output_tokens": 10, "total_tokens": 30},
    }


def _provider_shaped_legacy_request() -> dict:
    return {
        "model": "ignored-client-model",
        "instructions": "Released client planner instructions.",
        "input": [{"role": "user", "content": "Restart playback."}],
        "tools": [
            {
                "type": "function",
                "name": "submit_plan_v3",
                "parameters": {"type": "object"},
            }
        ],
        "tool_choice": {"type": "function", "name": "submit_plan_v3"},
        "parallel_tool_calls": False,
        "store": True,
    }


def _event(body: dict) -> dict:
    return {
        "requestContext": {
            "http": {"method": "POST"},
            "routeKey": "POST /v1/llm/v3/responses",
            "authorizer": {
                "jwt": {
                    "claims": {
                        "iss": proxy_config.APP_AUTH_ISSUER,
                        "aud": proxy_config.APP_AUTH_AUDIENCE,
                        "sub": "released-user",
                        "sid": "released-session",
                        "token_use": "access",
                    }
                }
            },
        },
        "rawPath": "/v1/llm/v3/responses",
        "headers": {"Authorization": "Bearer fixture-token"},
        "body": json.dumps(body),
        "isBase64Encoded": False,
    }


class _Reservation:
    allowed = True
    limit_reason = ""
    reserved_quota_prompts = 1
    reserved_grant_prompts = 0


class _UsageRepository:
    def load_user_context(self, user_id: str) -> dict:
        return {"user_id": user_id, "subscription_tier": "free", "tier": "free"}

    def reserve_usage(self, user_id: str, **kwargs: object) -> _Reservation:
        return _Reservation()

    def release_usage(self, user_id: str, **kwargs: object) -> None:
        return None

    def finalize_usage(self, user_id: str, **kwargs: object) -> None:
        return None

    def log_usage_event(self, **kwargs: object) -> None:
        return None

    def get_prompt_limit_status(self, user_id: str, **kwargs: object) -> dict:
        return {
            "daily": {"used": 0, "limit": 100, "remaining": 100, "resets_at": ""},
            "weekly": {"used": 0, "limit": 500, "remaining": 500, "resets_at": ""},
            "can_submit": True,
            "blocked_by": "",
            "extra_prompt_bank": {"remaining": 0, "consumed_first": True},
        }


class _Provider:
    name = "fake-provider"

    def __init__(
        self,
        *,
        payload: dict | None = None,
        error: Exception | None = None,
        status_code: int = 200,
    ) -> None:
        self.requests: list[dict] = []
        self.timeouts: list[int] = []
        self.payload = copy.deepcopy(payload) if payload is not None else _provider_payload()
        self.error = error
        self.status_code = status_code

    def forward_request(
        self, *, api_key: str, request_body: dict, timeout_seconds: int
    ) -> dict:
        self.requests.append(copy.deepcopy(request_body))
        self.timeouts.append(timeout_seconds)
        if self.error is not None:
            raise self.error
        return {
            "statusCode": self.status_code,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(self.payload),
        }


class _LambdaContext:
    aws_request_id = "compatibility-test"

    def get_remaining_time_in_millis(self) -> int:
        return 30_000


class V3ContractCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.usage = _UsageRepository()
        self.usage_patch = mock.patch.object(api_responses, "_usage_repo", self.usage)
        self.usage_patch.start()
        self.addCleanup(self.usage_patch.stop)

    def _call(
        self,
        body: dict,
        *,
        provider: _Provider | None = None,
        **flags: str,
    ) -> tuple[dict, _Provider]:
        provider = provider or _Provider()
        environment = {
            "AI_V3_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_V1_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_V2_ENABLED": "true",
            "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "true",
            **flags,
        }
        with mock.patch.dict(os.environ, environment, clear=False), mock.patch.object(
            api_responses, "_load_api_key", return_value="sk-test"
        ), mock.patch.object(api_responses, "get_provider", return_value=provider):
            response = api_responses.handler(_event(body), _LambdaContext())
        return response, provider

    def test_frozen_v1_contract_accepts_released_fixture_and_keeps_contract_3(self) -> None:
        request = _released_v1_request()
        validated = v3_server_contract_v1.validate_context_request(
            request,
            raw_body_bytes=len(json.dumps(request).encode("utf-8")),
        )
        provider_request = v3_server_contract_v1.build_provider_request(
            validated,
            model="gpt-5.6-luna",
            reasoning_effort="low",
            max_output_tokens=8192,
            prompt_cache_retention="24h",
            store=True,
        )
        plan = v3_server_contract_v1.parse_and_validate_provider_plan(
            _provider_payload(),
            command_types=validated["supported_command_types"],
            resource_refs_enabled=validated["resource_refs_enabled"],
        )
        envelope = v3_server_contract_v1.response_envelope(
            plan=plan,
            prompt_trace_id="released-v1-trace",
            request_id="request-1",
            fingerprint=v3_server_contract_v1.contract_fingerprint(
                command_types=validated["supported_command_types"],
                resource_refs_enabled=validated["resource_refs_enabled"],
            ),
        )

        self.assertEqual(v3_server_contract_v1.CONTRACT_VERSION, "mixroom_v3_server_contract_3")
        self.assertEqual(provider_request["tools"][0]["name"], "submit_plan_v3")
        self.assertEqual(set(envelope), {"schema_version", "plan", "trace"})
        self.assertEqual(envelope["trace"]["contract_version"], "mixroom_v3_server_contract_3")

    def test_frozen_v1_assets_match_the_released_contract_3_snapshots(self) -> None:
        actual = {
            name: hashlib.sha256((V1_ASSETS / name).read_bytes()).hexdigest()
            for name in V1_ASSET_SHA256
        }

        self.assertEqual(actual, V1_ASSET_SHA256)

    def test_frozen_v1_module_matches_the_reviewed_contract_3_snapshot(self) -> None:
        self.assertEqual(
            hashlib.sha256(V1_MODULE.read_bytes()).hexdigest(),
            V1_MODULE_SHA256,
        )

    def test_released_v1_matrix_uses_the_exact_frozen_provider_request_and_envelope(
        self,
    ) -> None:
        for scenario, request in _released_v1_request_matrix().items():
            with self.subTest(scenario=scenario):
                response, provider = self._call(request)
                validated = v3_server_contract_v1.validate_context_request(
                    request,
                    raw_body_bytes=len(json.dumps(request).encode("utf-8")),
                )
                expected_provider_request = v3_server_contract_v1.build_provider_request(
                    validated,
                    model="gpt-5.6-luna",
                    reasoning_effort="low",
                    max_output_tokens=8192,
                    prompt_cache_retention="24h",
                    store=True,
                )
                expected_plan = v3_server_contract_v1.parse_and_validate_provider_plan(
                    _provider_payload(),
                    command_types=validated["supported_command_types"],
                    resource_refs_enabled=validated["resource_refs_enabled"],
                )
                expected_envelope = v3_server_contract_v1.response_envelope(
                    plan=expected_plan,
                    prompt_trace_id=validated["prompt_trace_id"],
                    request_id=_LambdaContext.aws_request_id,
                    fingerprint=v3_server_contract_v1.contract_fingerprint(
                        command_types=validated["supported_command_types"],
                        resource_refs_enabled=validated["resource_refs_enabled"],
                    ),
                )

                self.assertEqual(response["statusCode"], 200)
                self.assertEqual(provider.requests, [expected_provider_request])
                self.assertEqual(provider.timeouts, [27])
                actual_envelope = json.loads(response["body"])
                self.assertEqual(
                    {
                        key: actual_envelope[key]
                        for key in ("schema_version", "plan", "trace")
                    },
                    expected_envelope,
                )
                self.assertEqual(
                    actual_envelope["prompt_rate_limit"],
                    self.usage.get_prompt_limit_status("released-user"),
                )

    def test_released_v1_invalid_provider_output_is_never_repaired_or_retried(
        self,
    ) -> None:
        provider = _Provider(payload={"id": "invalid", "output": []})

        response, provider = self._call(_released_v1_request(), provider=provider)

        self.assertEqual(response["statusCode"], 502)
        self.assertEqual(
            json.loads(response["body"])["error"]["code"],
            "v3_invalid_provider_output",
        )
        self.assertEqual(len(provider.requests), 1)
        self.assertEqual(provider.timeouts, [27])

    def test_released_v1_visible_text_behavior_remains_frozen(self) -> None:
        plan = _plan()
        plan["user_message"] = "ORIGINAL_REQUEST_VERBATIM:\nRestart playback."
        payload = _provider_payload()
        payload["output"][0]["arguments"] = json.dumps(plan)
        provider = _Provider(payload=payload)

        response, provider = self._call(_released_v1_request(), provider=provider)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"])["plan"], plan)
        self.assertEqual(len(provider.requests), 1)
        self.assertEqual(provider.timeouts, [27])

    def test_released_v1_timeout_keeps_the_structured_failure_boundary(self) -> None:
        provider = _Provider(error=TimeoutError("released V1 provider timeout"))

        response, provider = self._call(_released_v1_request(), provider=provider)

        self.assertEqual(response["statusCode"], 504)
        self.assertEqual(
            json.loads(response["body"])["error"]["code"],
            "v3_upstream_timeout",
        )
        self.assertEqual(len(provider.requests), 1)
        self.assertEqual(provider.timeouts, [27])

    def test_handler_routes_released_v1_and_updated_v2_independently(self) -> None:
        v1_response, v1_provider = self._call(_released_v1_request())
        v2_request = _released_v1_request()
        v2_request["request_contract"] = "mixroom_v3_context_v2"
        v2_response, v2_provider = self._call(v2_request)

        self.assertEqual(v1_response["statusCode"], 200)
        self.assertEqual(v2_response["statusCode"], 200)
        self.assertEqual(
            json.loads(v1_response["body"])["trace"]["contract_version"],
            "mixroom_v3_server_contract_3",
        )
        self.assertEqual(
            json.loads(v2_response["body"])["trace"]["contract_version"],
            "mixroom_v3_server_contract_6",
        )
        self.assertEqual(len(v1_provider.requests), 1)
        self.assertEqual(len(v2_provider.requests), 1)

    def test_v1_and_v2_kill_switches_are_independent(self) -> None:
        disabled_v1_response, disabled_v1_provider = self._call(
            _released_v1_request(),
            AI_V3_SERVER_CONTRACT_V1_ENABLED="false",
        )
        v2_request = _released_v1_request()
        v2_request["request_contract"] = "mixroom_v3_context_v2"
        enabled_v2_response, enabled_v2_provider = self._call(
            v2_request,
            AI_V3_SERVER_CONTRACT_V1_ENABLED="false",
        )
        disabled_v2_response, disabled_v2_provider = self._call(
            v2_request,
            AI_V3_SERVER_CONTRACT_V2_ENABLED="false",
        )
        enabled_v1_response, enabled_v1_provider = self._call(
            _released_v1_request(),
            AI_V3_SERVER_CONTRACT_V2_ENABLED="false",
        )

        self.assertEqual(disabled_v1_response["statusCode"], 503)
        self.assertEqual(enabled_v2_response["statusCode"], 200)
        self.assertEqual(disabled_v2_response["statusCode"], 503)
        self.assertEqual(enabled_v1_response["statusCode"], 200)
        self.assertEqual(
            json.loads(disabled_v1_response["body"])["error"]["code"],
            "v3_server_contract_disabled",
        )
        self.assertEqual(
            json.loads(disabled_v2_response["body"])["error"]["code"],
            "v3_server_contract_disabled",
        )
        self.assertEqual(disabled_v1_provider.requests, [])
        self.assertEqual(len(enabled_v2_provider.requests), 1)
        self.assertEqual(disabled_v2_provider.requests, [])
        self.assertEqual(len(enabled_v1_provider.requests), 1)

    def test_existing_umbrella_flag_enables_both_versions_by_default(self) -> None:
        v1_response, _ = self._call(
            _released_v1_request(),
            AI_V3_SERVER_CONTRACT_V1_ENABLED="",
            AI_V3_SERVER_CONTRACT_V2_ENABLED="",
        )
        v2_request = _released_v1_request()
        v2_request["request_contract"] = "mixroom_v3_context_v2"
        v2_response, _ = self._call(
            v2_request,
            AI_V3_SERVER_CONTRACT_V1_ENABLED="",
            AI_V3_SERVER_CONTRACT_V2_ENABLED="",
        )

        self.assertEqual(v1_response["statusCode"], 200)
        self.assertEqual(v2_response["statusCode"], 200)

    def test_existing_umbrella_flag_still_disables_both_context_versions(self) -> None:
        v1_response, v1_provider = self._call(
            _released_v1_request(),
            AI_V3_SERVER_CONTRACT_ENABLED="false",
        )
        v2_request = _released_v1_request()
        v2_request["request_contract"] = "mixroom_v3_context_v2"
        v2_response, v2_provider = self._call(
            v2_request,
            AI_V3_SERVER_CONTRACT_ENABLED="false",
        )

        self.assertEqual(v1_response["statusCode"], 503)
        self.assertEqual(v2_response["statusCode"], 503)
        self.assertEqual(v1_provider.requests, [])
        self.assertEqual(v2_provider.requests, [])

    def test_unknown_context_version_is_rejected_without_provider_call(self) -> None:
        request = _released_v1_request()
        request["request_contract"] = "mixroom_v3_context_future"

        response, provider = self._call(request)

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(
            json.loads(response["body"])["error"]["code"],
            "v3_request_contract_unsupported",
        )
        self.assertEqual(provider.requests, [])

    def test_provider_shaped_legacy_client_remains_independently_enabled(self) -> None:
        response, provider = self._call(
            _provider_shaped_legacy_request(),
            AI_V3_SERVER_CONTRACT_V1_ENABLED="false",
            AI_V3_SERVER_CONTRACT_V2_ENABLED="false",
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(provider.requests), 1)

    def test_all_version_flag_combinations_keep_v1_v2_and_legacy_independent(
        self,
    ) -> None:
        v2_request = _released_v1_request()
        v2_request["request_contract"] = "mixroom_v3_context_v2"
        paths = {
            "v1": _released_v1_request(),
            "v2": v2_request,
            "legacy": _provider_shaped_legacy_request(),
        }
        for umbrella_enabled in (False, True):
            for v1_enabled in (False, True):
                for v2_enabled in (False, True):
                    for legacy_enabled in (False, True):
                        flags = {
                            "AI_V3_SERVER_CONTRACT_ENABLED": str(
                                umbrella_enabled
                            ).lower(),
                            "AI_V3_SERVER_CONTRACT_V1_ENABLED": str(v1_enabled).lower(),
                            "AI_V3_SERVER_CONTRACT_V2_ENABLED": str(v2_enabled).lower(),
                            "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": str(
                                legacy_enabled
                            ).lower(),
                        }
                        expected = {
                            "v1": umbrella_enabled and v1_enabled,
                            "v2": umbrella_enabled and v2_enabled,
                            "legacy": legacy_enabled,
                        }
                        for path, request in paths.items():
                            with self.subTest(path=path, flags=flags):
                                response, provider = self._call(request, **flags)
                                self.assertEqual(
                                    response["statusCode"] == 200,
                                    expected[path],
                                )
                                self.assertEqual(
                                    len(provider.requests),
                                    1 if expected[path] else 0,
                                )


if __name__ == "__main__":
    unittest.main()
