#!/usr/bin/env python3
"""Run one capped, synthetic V3 latency sample against the live OpenAI API."""

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
PROVIDER_TIMEOUT_SECONDS = 27
FIXED_SCENARIOS = ("small", "medium", "product_max")
OUTPUT_PATH = Path("/tmp/pro4-v3-live-measurement.json")


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


def _measure(
    *,
    name: str,
    body: dict[str, Any],
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
        reasoning_effort="low",
        max_output_tokens=8192,
        prompt_cache_retention="24h",
        store=True,
    )
    upstream_request = build_openai_responses_request(provider_request)
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
            "scenario": name,
            "status_code": 504 if isinstance(error, TimeoutError) else 502,
            "provider_roundtrip_ms": elapsed_ms,
            "provider_timed_out": isinstance(error, TimeoutError),
            "error_type": type(error).__name__,
            "client_request_bytes": raw_body_bytes,
            "provider_request_bytes": _json_bytes(provider_request),
            "wire_request_bytes": len(json.dumps(upstream_request).encode("utf-8")),
            "plan_valid": False,
        }

    elapsed_ms = int((time.perf_counter() - started_at) * 1_000)
    observability = response.get("observability")
    if not isinstance(observability, dict):
        observability = {}
    status_code = int(response.get("statusCode") or 500)
    try:
        payload = json.loads(str(response.get("body") or "{}"))
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    plan_valid = False
    plan_command_count: int | None = None
    validation_error_code: str | None = None
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
        except v3_server_contract.V3ContractError as error:
            validation_error_code = error.code

    return {
        "scenario": name,
        "status_code": status_code,
        "provider_roundtrip_ms": _integer(
            observability.get("provider_roundtrip_ms")
        )
        or elapsed_ms,
        "provider_timed_out": False,
        "client_request_bytes": raw_body_bytes,
        "provider_request_bytes": _json_bytes(provider_request),
        "wire_request_bytes": len(json.dumps(upstream_request).encode("utf-8")),
        "plan_valid": plan_valid,
        "plan_command_count": plan_command_count,
        "validation_error_code": validation_error_code,
        **_usage(payload),
    }


def run() -> dict[str, Any]:
    api_key = _load_configured_api_key()
    if not api_key:
        raise RuntimeError("No OpenAI API key is configured.")
    fixtures = scenarios()
    started_at = time.perf_counter()
    measurements = [
        _measure(name=name, body=fixtures[name], api_key=api_key)
        for name in FIXED_SCENARIOS
    ]
    del api_key
    return {
        "measurement_contract": "pro4_v3_live_provider_one_shot_v1",
        "model": MODEL,
        "reasoning_effort": "low",
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
