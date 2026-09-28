#!/usr/bin/env python3
"""Run three capped one-shot V3 control samples against the live OpenAI API."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PROXY_SRC = ROOT / "backend" / "llm_proxy" / "src"
TOOL_DIR = Path(__file__).resolve().parent
for path in (PROXY_SRC, TOOL_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from common import v3_server_contract  # noqa: E402
from common.llm_contract import build_openai_responses_request  # noqa: E402
from common.llm_provider import get_provider  # noqa: E402
from handlers.api_responses import _extract_api_key_from_secret  # noqa: E402
from profile_v3_requests import _canonical_json, _json_bytes, scenarios  # noqa: E402


MODEL = "gpt-5.6-luna"
REASONING_EFFORT = "low"
PROVIDER_TIMEOUT_SECONDS = 105
MEASUREMENT_CONTRACT = "pro118_one_shot_control_v1"
FIXED_SCENARIOS = ("small", "product_max", "large_project")
OUTPUT_PATH = Path("/tmp/pro118-one-shot-baseline.json")

LIVE_CASES: dict[str, dict[str, Any]] = {
    "small": {
        "request": "Restart playback.",
        "expected_type": "transport.restart",
        "target_arguments": {},
        "value_arguments": {},
    },
    "product_max": {
        "request": "Transpose MIDI clip synthetic-clip-0002 up two semitones.",
        "expected_type": "midi.transpose",
        "target_arguments": {"clip_id": "synthetic-clip-0002"},
        "value_arguments": {"semitones": 2},
    },
    "large_project": {
        "request": "Rename row 1 to Lead Vocal.",
        "expected_type": "row.rename",
        "target_arguments": {"row_id": 1},
        "value_arguments": {"new_name": "Lead Vocal"},
    },
}


def _integer(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if value < 0:
        return None
    return int(value)


def _usage(payload: dict[str, Any]) -> dict[str, int | None]:
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        usage = {}
    input_details = usage.get("input_tokens_details")
    if not isinstance(input_details, dict):
        input_details = {}
    output_details = usage.get("output_tokens_details")
    if not isinstance(output_details, dict):
        output_details = {}
    return {
        "input_tokens": _integer(usage.get("input_tokens")),
        "cached_input_tokens": _integer(input_details.get("cached_tokens")),
        "output_tokens": _integer(usage.get("output_tokens")),
        "reasoning_tokens": _integer(output_details.get("reasoning_tokens")),
        "total_tokens": _integer(usage.get("total_tokens")),
    }


def _load_configured_api_key() -> str:
    direct = str(os.environ.get("LLM_API_KEY") or os.environ.get("OPENAI_API_KEY") or "").strip()
    if direct:
        return direct
    parameter_name = str(
        os.environ.get("LLM_API_KEY_PARAMETER_NAME")
        or os.environ.get("OPENAI_API_KEY_PARAMETER_NAME")
        or ""
    ).strip()
    if not parameter_name:
        return ""
    region = str(os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "").strip()
    command = [
        "aws",
        "ssm",
        "get-parameter",
        "--name",
        parameter_name,
        "--with-decryption",
        "--query",
        "Parameter.Value",
        "--output",
        "text",
    ]
    if region:
        command.extend(("--region", region))
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError("The encrypted OpenAI parameter could not be loaded.")
    secret = completed.stdout.strip()
    try:
        parsed: Any = json.loads(secret)
    except json.JSONDecodeError:
        parsed = secret
    return _extract_api_key_from_secret(parsed, "openai")


def _score_plan(plan: Any, case: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(plan, dict):
        return {"semantic_match": False, "result_category": "invalid_plan"}
    outcome = str(plan.get("outcome") or "")
    if outcome == "clarify":
        return {"semantic_match": False, "result_category": "clarification"}
    if outcome != "plan":
        return {"semantic_match": False, "result_category": "wrong_outcome"}
    commands = plan.get("commands")
    if not isinstance(commands, list) or len(commands) != 1:
        return {"semantic_match": False, "result_category": "wrong_operation"}
    command = commands[0]
    if not isinstance(command, dict) or command.get("type") != case["expected_type"]:
        return {"semantic_match": False, "result_category": "wrong_operation"}
    arguments = command.get("arguments")
    if not isinstance(arguments, dict):
        return {"semantic_match": False, "result_category": "invalid_plan"}
    if any(
        arguments.get(key) != value
        for key, value in case["target_arguments"].items()
    ):
        return {"semantic_match": False, "result_category": "wrong_target"}
    if any(
        arguments.get(key) != value
        for key, value in case["value_arguments"].items()
    ):
        return {"semantic_match": False, "result_category": "wrong_value"}
    return {"semantic_match": True, "result_category": "success"}


def _measure(
    *,
    name: str,
    body: dict[str, Any],
    case: dict[str, Any],
    api_key: str,
) -> dict[str, Any]:
    raw_body_bytes = _json_bytes(body)
    validated = v3_server_contract.validate_context_request(
        body,
        raw_body_bytes=raw_body_bytes,
    )
    provider_request = v3_server_contract.build_provider_request(
        validated,
        model=MODEL,
        reasoning_effort=REASONING_EFFORT,
        prompt_cache_retention="24h",
        store=True,
    )
    upstream_request = build_openai_responses_request(provider_request)
    provider_request_bytes = _json_bytes(provider_request)
    wire_request_bytes = len(json.dumps(upstream_request).encode("utf-8"))
    common_measurement = {
        "scenario": name,
        "client_request_bytes": raw_body_bytes,
        "core_context_bytes": _json_bytes(validated["core_context"]),
        "provider_request_bytes": provider_request_bytes,
        "wire_request_bytes": wire_request_bytes,
        "max_output_tokens": provider_request["max_output_tokens"],
        "effective_command_type_count": len(validated["supported_command_types"]),
        "tool_command_variant_count": len(
            provider_request["tools"][0]["parameters"]["properties"]["commands"][
                "items"
            ]["anyOf"]
        ),
    }
    started_at = time.perf_counter()
    try:
        response = get_provider("openai").forward_request(
            api_key=api_key,
            request_body=provider_request,
            timeout_seconds=PROVIDER_TIMEOUT_SECONDS,
        )
    except Exception as error:
        elapsed_ms = int((time.perf_counter() - started_at) * 1_000)
        return {
            **common_measurement,
            "status_code": 504 if isinstance(error, TimeoutError) else 502,
            "provider_roundtrip_ms": elapsed_ms,
            "provider_timed_out": isinstance(error, TimeoutError),
            "error_type": type(error).__name__,
            "plan_valid": False,
            "semantic_match": False,
            "result_category": (
                "timeout" if isinstance(error, TimeoutError) else "provider_error"
            ),
        }

    elapsed_ms = int((time.perf_counter() - started_at) * 1_000)
    observability = response.get("observability")
    if not isinstance(observability, dict):
        observability = {}
    status_code = int(response.get("statusCode") or 500)
    raw_response_body = str(response.get("body") or "{}")
    try:
        payload = json.loads(raw_response_body)
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    plan_valid = False
    plan_command_count: int | None = None
    serialized_plan_bytes: int | None = None
    validation_error_code: str | None = None
    semantic = {"semantic_match": False, "result_category": "provider_error"}
    if 200 <= status_code < 300:
        try:
            plan = v3_server_contract.parse_and_validate_provider_plan(
                payload,
                command_types=validated["supported_command_types"],
                resource_refs_enabled=validated["resource_refs_enabled"],
                capability_surface=validated["capability_surface"],
                original_request=validated["original_request"],
            )
            plan_valid = True
            plan_command_count = len(plan.get("commands") or [])
            serialized_plan_bytes = _json_bytes(plan)
            semantic = _score_plan(plan, case)
        except v3_server_contract.V3ContractError as error:
            validation_error_code = error.code
            semantic = {"semantic_match": False, "result_category": "invalid_plan"}

    return {
        **common_measurement,
        "status_code": status_code,
        "provider_roundtrip_ms": _integer(
            observability.get("provider_roundtrip_ms")
        )
        or elapsed_ms,
        "provider_timed_out": False,
        "provider_response_bytes": len(raw_response_body.encode("utf-8")),
        "plan_valid": plan_valid,
        "plan_command_count": plan_command_count,
        "serialized_plan_bytes": serialized_plan_bytes,
        "validation_error_code": validation_error_code,
        **semantic,
        **_usage(payload),
    }


def run() -> dict[str, Any]:
    api_key = _load_configured_api_key()
    if not api_key:
        raise RuntimeError("No OpenAI API key is configured.")
    fixtures = scenarios()
    if tuple(LIVE_CASES) != FIXED_SCENARIOS or len(set(FIXED_SCENARIOS)) != 3:
        raise RuntimeError("The live one-shot baseline must contain exactly three cases.")
    started_at = time.perf_counter()
    measurements = []
    retry_env_name = "LLM_UPSTREAM_NETWORK_RETRY_ATTEMPTS"
    previous_retry_attempts = os.environ.get(retry_env_name)
    os.environ[retry_env_name] = "1"
    try:
        for name in FIXED_SCENARIOS:
            body = json.loads(json.dumps(fixtures[name]))
            case = LIVE_CASES[name]
            body["original_request"] = case["request"]
            measurements.append(
                _measure(name=name, body=body, case=case, api_key=api_key)
            )
    finally:
        if previous_retry_attempts is None:
            os.environ.pop(retry_env_name, None)
        else:
            os.environ[retry_env_name] = previous_retry_attempts
    del api_key
    return {
        "measurement_contract": MEASUREMENT_CONTRACT,
        "architecture": "v3_one_shot_server_contract",
        "contract_version": v3_server_contract.CONTRACT_VERSION,
        "model": MODEL,
        "reasoning_effort": REASONING_EFFORT,
        "provider_timeout_seconds": PROVIDER_TIMEOUT_SECONDS,
        "request_count": len(measurements),
        "total_wall_ms": int((time.perf_counter() - started_at) * 1_000),
        "measurements": measurements,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--execute-live",
        action="store_true",
        help="Acknowledge exactly three billable synthetic OpenAI requests.",
    )
    args = parser.parse_args()
    if not args.execute_live:
        parser.error("refusing live requests without --execute-live")
    report = run()
    serialized = _canonical_json(report) + "\n"
    OUTPUT_PATH.write_text(serialized, encoding="utf-8")
    print(serialized, end="")


if __name__ == "__main__":
    main()
