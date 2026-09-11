#!/usr/bin/env python3
"""Serve the real Mixroom V3 Lambda handler through a sealed localhost bridge.

The bridge injects a deterministic provider and in-memory usage repository. It
never calls OpenAI, AWS, PostHog, Sentry, or any other network service.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
from contextlib import redirect_stdout
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any


# Do not let boto3 credential discovery contact an instance-metadata endpoint
# while the backend module is imported for this deliberately offline tool.
_ORIGINAL_METADATA_DISABLED = os.environ.get("AWS_EC2_METADATA_DISABLED")
os.environ["AWS_EC2_METADATA_DISABLED"] = "true"


ROOT = Path(__file__).resolve().parents[2]
PROXY_SRC = ROOT / "backend" / "llm_proxy" / "src"
TOOL_DIR = Path(__file__).resolve().parent
if str(PROXY_SRC) not in sys.path:
    sys.path.insert(0, str(PROXY_SRC))
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

from common import config as proxy_config  # noqa: E402
from common import v3_server_contract  # noqa: E402
from handlers import api_responses  # noqa: E402
from handlers import api_responses_v3_rest  # noqa: E402

if _ORIGINAL_METADATA_DISABLED is None:
    os.environ.pop("AWS_EC2_METADATA_DISABLED", None)
else:
    os.environ["AWS_EC2_METADATA_DISABLED"] = _ORIGINAL_METADATA_DISABLED

from analyze_v3_production_measurement import (  # noqa: E402
    BACKEND_ALLOWED_FIELDS,
)


SCENARIOS = (
    "success",
    "timeout",
    "upstream_error",
    "invalid_output",
    "semantic_repair_success",
    "semantic_repair_failure",
)
TRANSPORT_MODES = ("standard", "long")
_MAX_DELAY_MS = 110_000
_STANDARD_MAX_PROVIDER_TIMEOUT_SECONDS = 27
_LONG_MAX_PROVIDER_TIMEOUT_SECONDS = 105


class _ReservationResult:
    allowed = True
    limit_reason = ""
    reserved_quota_prompts = 1
    reserved_grant_prompts = 0


class InMemoryUsageRepository:
    """Minimal usage seam with no persistence or external dependencies."""

    def __init__(self) -> None:
        self.reserve_count = 0
        self.release_count = 0
        self.finalize_count = 0

    def load_user_context(self, user_id: str) -> dict[str, Any]:
        return {
            "user_id": user_id,
            "subscription_tier": "free",
            "tier": "free",
        }

    def reserve_usage(self, user_id: str, **kwargs: object) -> _ReservationResult:
        del user_id, kwargs
        self.reserve_count += 1
        return _ReservationResult()

    def release_usage(self, user_id: str, **kwargs: object) -> None:
        del user_id, kwargs
        self.release_count += 1

    def finalize_usage(self, user_id: str, **kwargs: object) -> None:
        del user_id, kwargs
        self.finalize_count += 1

    def log_usage_event(self, **kwargs: object) -> None:
        del kwargs

    def get_prompt_limit_status(self, user_id: str, **kwargs: object) -> dict[str, Any]:
        del user_id, kwargs
        return {
            "daily": {
                "used": 0,
                "limit": 100,
                "remaining": 100,
                "resets_at": "2099-01-02T00:00:00+00:00",
            },
            "weekly": {
                "used": 0,
                "limit": 500,
                "remaining": 500,
                "resets_at": "2099-01-08T00:00:00+00:00",
            },
            "can_submit": True,
            "blocked_by": "",
            "extra_prompt_bank": {"remaining": 0, "consumed_first": True},
        }


def _plan(*, unsafe: bool = False) -> dict[str, Any]:
    return {
        "schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
        "outcome": "respond",
        "user_message": (
            "ORIGINAL_REQUEST_VERBATIM:\nRestart playback."
            if unsafe
            else "The deterministic local bridge completed the request."
        ),
        "commands": [],
        "question_options": [],
    }


def _provider_payload(plan: dict[str, Any], attempt: int) -> dict[str, Any]:
    return {
        "id": f"local-response-{attempt}",
        "output": [
            {
                "type": "function_call",
                "name": "submit_plan_v3",
                "arguments": json.dumps(plan, separators=(",", ":")),
            }
        ],
        "usage": {
            "input_tokens": 100,
            "input_tokens_details": {"cached_tokens": 0},
            "output_tokens": 20,
            "output_tokens_details": {"reasoning_tokens": 0},
            "total_tokens": 120,
        },
    }


class DeterministicProvider:
    name = "local-deterministic-provider"

    def __init__(self, *, scenario: str, delay_ms: int) -> None:
        if scenario not in SCENARIOS:
            raise ValueError(f"Unsupported local scenario: {scenario}")
        if delay_ms < 0 or delay_ms > _MAX_DELAY_MS:
            raise ValueError(f"delay_ms must be between 0 and {_MAX_DELAY_MS}")
        self.scenario = scenario
        self.delay_ms = delay_ms
        self.attempt_count = 0
        self.timeout_seconds: list[int] = []
        self.request_body_bytes: list[int] = []

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: dict[str, Any],
        timeout_seconds: int,
    ) -> dict[str, Any]:
        if api_key != "local-test-key":
            raise RuntimeError("The local bridge received an unexpected API key.")
        self.attempt_count += 1
        self.timeout_seconds.append(timeout_seconds)
        self.request_body_bytes.append(
            len(
                json.dumps(
                    request_body,
                    ensure_ascii=False,
                    separators=(",", ":"),
                    sort_keys=True,
                ).encode("utf-8")
            )
        )

        timeout_ms = max(timeout_seconds, 0) * 1_000
        if self.scenario == "timeout" or self.delay_ms >= timeout_ms:
            if self.delay_ms:
                time.sleep(min(self.delay_ms, timeout_ms) / 1_000)
            raise TimeoutError("deterministic local provider timeout")
        if self.delay_ms:
            time.sleep(self.delay_ms / 1_000)
        if self.scenario == "upstream_error":
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": {"code": "synthetic_upstream"}}),
            }
        if self.scenario == "invalid_output":
            payload = {
                "id": "local-invalid-output",
                "output": [],
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 5,
                    "total_tokens": 105,
                },
            }
        elif self.scenario == "semantic_repair_success":
            payload = _provider_payload(
                _plan(unsafe=self.attempt_count == 1),
                self.attempt_count,
            )
        elif self.scenario == "semantic_repair_failure":
            payload = _provider_payload(_plan(unsafe=True), self.attempt_count)
        else:
            payload = _provider_payload(_plan(), self.attempt_count)
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(payload),
        }


class _LambdaContext:
    def __init__(self, remaining_time_seconds: int) -> None:
        self._remaining_ms = remaining_time_seconds * 1_000

    def get_remaining_time_in_millis(self) -> int:
        return self._remaining_ms


class LocalBackend:
    """Invoke the handler with all external seams replaced locally."""

    def __init__(
        self,
        *,
        scenario: str,
        delay_ms: int,
        provider_timeout_seconds: int,
        transport_mode: str,
    ) -> None:
        if transport_mode not in TRANSPORT_MODES:
            raise ValueError(f"Unsupported transport mode: {transport_mode}")
        max_timeout = (
            _LONG_MAX_PROVIDER_TIMEOUT_SECONDS
            if transport_mode == "long"
            else _STANDARD_MAX_PROVIDER_TIMEOUT_SECONDS
        )
        if provider_timeout_seconds < 1 or provider_timeout_seconds > max_timeout:
            raise ValueError(
                "provider_timeout_seconds must be between 1 and "
                f"{max_timeout} for {transport_mode} mode"
            )
        self.scenario = scenario
        self.delay_ms = delay_ms
        self.provider_timeout_seconds = provider_timeout_seconds
        self.transport_mode = transport_mode
        self.pitch_repair_counts = dict(selected=0, applied=0, ineligible=0, failure=0)
        self.lambda_timeout_seconds = (
            115 if transport_mode == "long" else provider_timeout_seconds + 2
        )
        self.usage = InMemoryUsageRepository()
        self.providers: list[DeterministicProvider] = []

    def invoke(
        self,
        raw_body: str,
        *,
        request_number: int,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        provider = DeterministicProvider(
            scenario=self.scenario,
            delay_ms=self.delay_ms,
        )
        self.providers.append(provider)
        claims = {
            "iss": proxy_config.APP_AUTH_ISSUER,
            "aud": proxy_config.APP_AUTH_AUDIENCE,
            "sub": "local-v3-test-user",
            "sid": "local-v3-test-session",
            "token_use": "access",
        }
        request_id = f"local-bridge-{request_number}"
        if self.transport_mode == "long":
            event = {
                "resource": "/v1/llm/v3/responses",
                "path": "/v1/llm/v3/responses",
                "httpMethod": "POST",
                "requestContext": {
                    "requestId": request_id,
                    "httpMethod": "POST",
                    "authorizer": {"claims": claims},
                },
                "headers": {"Authorization": "Bearer local-bridge-token"},
                "body": raw_body,
                "isBase64Encoded": False,
            }
            entrypoint = api_responses_v3_rest.handler
        else:
            event = {
                "requestContext": {
                    "requestId": request_id,
                    "http": {"method": "POST"},
                    "routeKey": "POST /v1/llm/v3/responses",
                    "authorizer": {"jwt": {"claims": claims}},
                },
                "rawPath": "/v1/llm/v3/responses",
                "headers": {"Authorization": "Bearer local-bridge-token"},
                "body": raw_body,
                "isBase64Encoded": False,
            }
            entrypoint = api_responses.handler
        replacements: dict[str, Any] = {
            "_usage_repo": self.usage,
            "get_provider": lambda _name: provider,
            "_load_api_key": lambda _name="openai": "local-test-key",
            "get_ai_feature_runtime": lambda _feature, fallback_model: {
                "model": fallback_model,
                "source": "local_bridge",
            },
            "capture_event": lambda *args, **kwargs: None,
            "capture_exception": lambda *args, **kwargs: None,
        }
        originals = {
            name: getattr(api_responses, name)
            for name in replacements
        }
        environment_keys = {
            "AI_V3_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_ENABLED": "true",
            "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "false",
            "AI_V3_TIMEOUT_SECONDS": str(self.provider_timeout_seconds),
            "AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS": str(
                _LONG_MAX_PROVIDER_TIMEOUT_SECONDS
                if self.transport_mode == "long"
                else _STANDARD_MAX_PROVIDER_TIMEOUT_SECONDS
            ),
            "LLM_PROVIDER": "openai",
        }
        original_environment = {
            key: os.environ.get(key)
            for key in environment_keys
        }
        output = io.StringIO()
        try:
            for name, replacement in replacements.items():
                setattr(api_responses, name, replacement)
            os.environ.update(environment_keys)
            with redirect_stdout(output):
                response = entrypoint(
                    event,
                    _LambdaContext(self.lambda_timeout_seconds),
                )
        finally:
            for name, original in originals.items():
                setattr(api_responses, name, original)
            for key, original in original_environment.items():
                if original is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = original

        log_lines = output.getvalue().strip().splitlines()
        if not log_lines:
            raise RuntimeError("The local handler produced no final structured log.")
        final_log = json.loads(log_lines[-1])
        for key in self.pitch_repair_counts:
            self.pitch_repair_counts[key] += bool(final_log.get(f"v3_pitch_repair_{key}"))
        safe_measurement = {
            key: value
            for key, value in final_log.items()
            if key in BACKEND_ALLOWED_FIELDS and key not in {"@ptr", "prompt_trace_id"}
        }
        safe_measurement["@timestamp"] = datetime.now(timezone.utc).isoformat()
        print(
            json.dumps(
                {"message": "Local V3 backend measurement", **safe_measurement},
                sort_keys=True,
            ),
            flush=True,
        )
        return response, safe_measurement


class LocalV3BridgeServer(HTTPServer):
    allow_reuse_address = True

    def __init__(
        self,
        server_address: tuple[str, int],
        handler_class: type[BaseHTTPRequestHandler],
        *,
        backend: LocalBackend,
    ) -> None:
        super().__init__(server_address, handler_class)
        self.backend = backend
        self.measurements: list[dict[str, Any]] = []
        self.bridge_records: list[dict[str, Any]] = []


class LocalV3BridgeHandler(BaseHTTPRequestHandler):
    server: LocalV3BridgeServer

    def log_message(self, format: str, *args: object) -> None:
        del format, args

    def _write_json(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/_local/health":
            self._write_json(
                200,
                {
                    "ok": True,
                    "scenario": self.server.backend.scenario,
                    "transport_mode": self.server.backend.transport_mode,
                    "provider_timeout_seconds": self.server.backend.provider_timeout_seconds,
                    "lambda_timeout_seconds": self.server.backend.lambda_timeout_seconds,
                    "network_mode": "loopback_only",
                    "provider_mode": "deterministic_fake",
                    "request_count": len(self.server.measurements),
                    "provider_attempt_count": sum(
                        provider.attempt_count
                        for provider in self.server.backend.providers
                    ),
                    "usage_reserve_count": self.server.backend.usage.reserve_count,
                    "usage_finalize_count": self.server.backend.usage.finalize_count,
                    "usage_release_count": self.server.backend.usage.release_count,
                    "pitch_repair_counts": self.server.backend.pitch_repair_counts,
                },
            )
            return
        if self.path == "/_local/cloudwatch-export":
            results = [
                [
                    {
                        "field": key,
                        "value": (
                            str(value).lower()
                            if isinstance(value, bool)
                            else str(value)
                        ),
                    }
                    for key, value in sorted(measurement.items())
                ]
                for measurement in self.server.measurements
            ]
            self._write_json(200, {"results": results})
            return
        self._write_json(404, {"error": "local_route_not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/llm/v3/responses":
            self._write_json(404, {"error": "local_route_not_found"})
            return
        try:
            content_length = int(self.headers.get("Content-Length") or "")
        except ValueError:
            self._write_json(411, {"error": "content_length_required"})
            return
        # The listener must be able to read the largest recognized contract-6
        # request before the real handler can select legacy or dynamic policy.
        # The handler remains authoritative and rejects oversized/legacy input
        # before usage reservation or provider access.
        if (
            content_length < 0
            or content_length > v3_server_contract.DYNAMIC_MAX_REQUEST_BYTES
        ):
            self._write_json(413, {"error": "local_request_too_large"})
            return
        started_at = time.perf_counter()
        try:
            raw_body = self.rfile.read(content_length).decode("utf-8")
        except UnicodeDecodeError:
            self._write_json(400, {"error": "request_must_be_utf8"})
            return
        request_number = len(self.server.measurements) + 1
        response, measurement = self.server.backend.invoke(
            raw_body,
            request_number=request_number,
        )
        response_body = str(response.get("body") or "")
        status_code = int(response.get("statusCode") or 500)
        encoded_response = response_body.encode("utf-8")
        client_disconnected = False
        try:
            self.send_response(status_code)
            headers = response.get("headers")
            if isinstance(headers, dict):
                for key, value in headers.items():
                    if str(key).lower() not in {"content-length", "connection"}:
                        self.send_header(str(key), str(value))
            self.send_header("Content-Length", str(len(encoded_response)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(encoded_response)
        except (BrokenPipeError, ConnectionResetError):
            client_disconnected = True

        bridge_total_ms = max(int((time.perf_counter() - started_at) * 1_000), 0)
        handler_ms = int(measurement.get("latency_ms") or 0)
        bridge_record = {
            "scenario": self.server.backend.scenario,
            "transport_mode": self.server.backend.transport_mode,
            "status_code": status_code,
            "request_bytes": content_length,
            "response_bytes": len(encoded_response),
            "bridge_total_ms": bridge_total_ms,
            "handler_ms": handler_ms,
            "bridge_overhead_ms": max(bridge_total_ms - handler_ms, 0),
            "client_disconnected": client_disconnected,
        }
        self.server.measurements.append(measurement)
        self.server.bridge_records.append(bridge_record)
        print(
            json.dumps(
                {"message": "Local V3 bridge request complete", **bridge_record},
                sort_keys=True,
            ),
            flush=True,
        )


def create_server(
    *,
    port: int,
    scenario: str = "success",
    delay_ms: int = 0,
    provider_timeout_seconds: int | None = None,
    transport_mode: str = "standard",
) -> LocalV3BridgeServer:
    if provider_timeout_seconds is None:
        provider_timeout_seconds = (
            _LONG_MAX_PROVIDER_TIMEOUT_SECONDS
            if transport_mode == "long"
            else _STANDARD_MAX_PROVIDER_TIMEOUT_SECONDS
        )
    backend = LocalBackend(
        scenario=scenario,
        delay_ms=delay_ms,
        provider_timeout_seconds=provider_timeout_seconds,
        transport_mode=transport_mode,
    )
    return LocalV3BridgeServer(
        ("127.0.0.1", port),
        LocalV3BridgeHandler,
        backend=backend,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--scenario", choices=SCENARIOS, default="success")
    parser.add_argument("--transport", choices=TRANSPORT_MODES, default="standard")
    parser.add_argument("--delay-ms", type=int, default=0)
    parser.add_argument("--provider-timeout-seconds", type=int)
    args = parser.parse_args()
    if args.port < 0 or args.port > 65_535:
        parser.error("--port must be between 0 and 65535")
    if args.delay_ms < 0 or args.delay_ms > _MAX_DELAY_MS:
        parser.error(f"--delay-ms must be between 0 and {_MAX_DELAY_MS}")
    provider_timeout_seconds = args.provider_timeout_seconds
    max_provider_timeout_seconds = (
        _LONG_MAX_PROVIDER_TIMEOUT_SECONDS
        if args.transport == "long"
        else _STANDARD_MAX_PROVIDER_TIMEOUT_SECONDS
    )
    if provider_timeout_seconds is None:
        provider_timeout_seconds = max_provider_timeout_seconds
    if not 1 <= provider_timeout_seconds <= max_provider_timeout_seconds:
        parser.error(
            "--provider-timeout-seconds must be between 1 and "
            f"{max_provider_timeout_seconds} for {args.transport} mode"
        )

    server = create_server(
        port=args.port,
        scenario=args.scenario,
        delay_ms=args.delay_ms,
        provider_timeout_seconds=provider_timeout_seconds,
        transport_mode=args.transport,
    )
    print(
        json.dumps(
            {
                "message": "Local V3 bridge ready",
                "url": f"http://127.0.0.1:{server.server_port}",
                "scenario": args.scenario,
                "transport_mode": args.transport,
                "delay_ms": args.delay_ms,
                "provider_timeout_seconds": provider_timeout_seconds,
                "lambda_timeout_seconds": server.backend.lambda_timeout_seconds,
                "external_calls": False,
            },
            sort_keys=True,
        ),
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
