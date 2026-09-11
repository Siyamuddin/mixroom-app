#!/usr/bin/env python3
"""Run the real V3 handler and OpenAI provider behind a gated loopback bridge.

Unlike local_v3_bridge.py, this tool makes billable OpenAI requests. It keeps
authentication, usage accounting, telemetry, and project data local. The
server refuses to start without an explicit live acknowledgement and enforces
an immutable request cap for each process.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PROXY_SRC = ROOT / "backend" / "llm_proxy" / "src"
TOOL_DIR = Path(__file__).resolve().parent
for path in (PROXY_SRC, TOOL_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from common import config as proxy_config  # noqa: E402
from common.llm_provider import get_provider as get_live_provider  # noqa: E402
from handlers import api_responses  # noqa: E402
from handlers import api_responses_v3_rest  # noqa: E402
from analyze_v3_production_measurement import BACKEND_ALLOWED_FIELDS  # noqa: E402
from local_v3_bridge import (  # noqa: E402
    InMemoryUsageRepository,
    LocalV3BridgeHandler,
    LocalV3BridgeServer,
    _LambdaContext,
)
from measure_v3_live_provider import _load_configured_api_key  # noqa: E402


_MAX_REQUESTS = 60
_MAX_PROVIDER_TIMEOUT_SECONDS = 105


class CountingLiveProvider:
    """Count calls while delegating unchanged requests to the real provider."""

    name = "openai"

    def __init__(self) -> None:
        self._provider = get_live_provider("openai")
        self.attempt_count = 0
        self.timeout_seconds: list[int] = []
        self.request_body_bytes: list[int] = []
        self.last_rejection: dict[str, Any] | None = None
        self.last_exception: dict[str, str] | None = None

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: dict[str, Any],
        timeout_seconds: int,
    ) -> dict[str, Any]:
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
        try:
            response = self._provider.forward_request(
                api_key=api_key,
                request_body=request_body,
                timeout_seconds=timeout_seconds,
            )
        except Exception as error:
            self.last_exception = {
                "exception_type": type(error).__name__,
                "cause_type": type(error.__cause__).__name__
                if error.__cause__ is not None
                else "",
                "context_type": type(error.__context__).__name__
                if error.__context__ is not None
                else "",
            }
            raise
        status_code = int(response.get("statusCode") or 500)
        if not 200 <= status_code < 300:
            error_type = ""
            error_code = ""
            error_param = ""
            try:
                payload = json.loads(str(response.get("body") or "{}"))
                error = payload.get("error") if isinstance(payload, dict) else None
                if isinstance(error, dict):
                    error_type = str(error.get("type") or "")
                    error_code = str(error.get("code") or "")
                    error_param = str(error.get("param") or "")
            except (TypeError, ValueError):
                pass
            self.last_rejection = {
                "status_code": status_code,
                "error_type": error_type,
                "error_code": error_code,
                "error_param": error_param,
            }
        return response


class LiveLocalBackend:
    """Invoke the real handler with only external state seams replaced."""

    scenario = "live_provider"
    transport_mode = "long"
    provider_timeout_seconds = _MAX_PROVIDER_TIMEOUT_SECONDS
    lambda_timeout_seconds = 115

    def __init__(self, *, api_key: str) -> None:
        if not api_key.strip():
            raise ValueError("A non-empty API key is required.")
        self._api_key = api_key
        self.pitch_repair_counts = dict(selected=0, applied=0, ineligible=0, failure=0)
        self.usage = InMemoryUsageRepository()
        self.providers: list[CountingLiveProvider] = []

    def invoke(
        self,
        raw_body: str,
        *,
        request_number: int,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        provider = CountingLiveProvider()
        self.providers.append(provider)
        claims = {
            "iss": proxy_config.APP_AUTH_ISSUER,
            "aud": proxy_config.APP_AUTH_AUDIENCE,
            "sub": "local-v3-language-eval-user",
            "sid": "local-v3-language-eval-session",
            "token_use": "access",
        }
        request_id = f"local-live-language-{request_number}"
        event = {
            "resource": "/v1/llm/v3/responses",
            "path": "/v1/llm/v3/responses",
            "httpMethod": "POST",
            "requestContext": {
                "requestId": request_id,
                "httpMethod": "POST",
                "authorizer": {"claims": claims},
            },
            "headers": {"Authorization": "Bearer local-live-eval-token"},
            "body": raw_body,
            "isBase64Encoded": False,
        }
        replacements: dict[str, Any] = {
            "_usage_repo": self.usage,
            "get_provider": lambda _name: provider,
            "_load_api_key": lambda _name="openai": self._api_key,
            "get_ai_feature_runtime": lambda _feature, fallback_model: {
                "model": fallback_model,
                "source": "local_live_eval",
            },
            "capture_event": lambda *args, **kwargs: None,
            "capture_exception": lambda *args, **kwargs: None,
        }
        originals = {name: getattr(api_responses, name) for name in replacements}
        environment = {
            "AI_V3_ENABLED": "true",
            "AI_V3_SERVER_CONTRACT_ENABLED": "true",
            "AI_V3_LEGACY_CLIENT_CONTRACT_ENABLED": "false",
            "AI_V3_TIMEOUT_SECONDS": str(_MAX_PROVIDER_TIMEOUT_SECONDS),
            "AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS": str(
                _MAX_PROVIDER_TIMEOUT_SECONDS
            ),
            "LLM_PROVIDER": "openai",
        }
        original_environment = {key: os.environ.get(key) for key in environment}
        output = io.StringIO()
        try:
            for name, replacement in replacements.items():
                setattr(api_responses, name, replacement)
            os.environ.update(environment)
            with redirect_stdout(output):
                response = api_responses_v3_rest.handler(
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
                {"message": "Local live V3 backend measurement", **safe_measurement},
                sort_keys=True,
            ),
            flush=True,
        )
        if provider.last_rejection is not None:
            print(
                json.dumps(
                    {
                        "message": "Local live provider rejected request",
                        **provider.last_rejection,
                    },
                    sort_keys=True,
                ),
                flush=True,
            )
        if provider.last_exception is not None:
            print(
                json.dumps(
                    {
                        "message": "Local live provider raised exception",
                        **provider.last_exception,
                    },
                    sort_keys=True,
                ),
                flush=True,
            )
        return response, safe_measurement


class CappedLiveServer(LocalV3BridgeServer):
    def __init__(self, *args: Any, max_requests: int, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.max_requests = max_requests


class CappedLiveHandler(LocalV3BridgeHandler):
    server: CappedLiveServer

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/_local/health":
            self._write_json(
                200,
                {
                    "ok": True,
                    "network_mode": "loopback_only",
                    "provider_mode": "live_openai",
                    "request_count": len(self.server.measurements),
                    "max_requests": self.server.max_requests,
                    "provider_attempt_count": sum(
                        provider.attempt_count
                        for provider in self.server.backend.providers
                    ),
                    "pitch_repair_counts": self.server.backend.pitch_repair_counts,
                },
            )
            return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        if len(self.server.measurements) >= self.server.max_requests:
            self._write_json(429, {"error": "local_live_request_cap_reached"})
            return
        super().do_POST()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--execute-live",
        action="store_true",
        help="Acknowledge billable OpenAI requests from the local app.",
    )
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--max-requests", type=int, required=True)
    args = parser.parse_args()
    if not args.execute_live:
        parser.error("refusing live requests without --execute-live")
    if not 1 <= args.max_requests <= _MAX_REQUESTS:
        parser.error(f"--max-requests must be between 1 and {_MAX_REQUESTS}")
    if not 1 <= args.port <= 65_535:
        parser.error("--port must be between 1 and 65535")

    if not os.environ.get("SSL_CERT_FILE"):
        try:
            import certifi

            ca_bundle = Path(certifi.where())
            if ca_bundle.is_file():
                os.environ["SSL_CERT_FILE"] = str(ca_bundle)
        except ImportError:
            pass

    api_key = _load_configured_api_key()
    if not api_key:
        parser.error("No OpenAI API key is configured.")
    backend = LiveLocalBackend(api_key=api_key)
    del api_key
    server = CappedLiveServer(
        ("127.0.0.1", args.port),
        CappedLiveHandler,
        backend=backend,
        max_requests=args.max_requests,
    )
    print(
        json.dumps(
            {
                "message": "Local live V3 bridge ready",
                "url": f"http://127.0.0.1:{server.server_port}",
                "provider_mode": "live_openai",
                "max_requests": args.max_requests,
                "external_calls": ["OpenAI"],
                "persistent_external_writes": False,
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
