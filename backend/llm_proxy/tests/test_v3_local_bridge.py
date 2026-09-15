from __future__ import annotations

import importlib.util
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from contextlib import contextmanager, redirect_stdout
from io import StringIO
from pathlib import Path
from typing import Iterator
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
TOOL_DIR = ROOT / "tool" / "ai_v3_eval"
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))


def _load_tool(name: str):
    path = TOOL_DIR / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {path}.")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


analyzer = _load_tool("analyze_v3_production_measurement")
profiler = _load_tool("profile_v3_requests")
bridge = _load_tool("local_v3_bridge")
live_measurement = _load_tool("measure_v3_live_provider")


@contextmanager
def _running_server(
    *,
    scenario: str = "success",
    delay_ms: int = 0,
    provider_timeout_seconds: int | None = None,
    transport_mode: str = "standard",
) -> Iterator[bridge.LocalV3BridgeServer]:
    server = bridge.create_server(
        port=0,
        scenario=scenario,
        delay_ms=delay_ms,
        provider_timeout_seconds=provider_timeout_seconds,
        transport_mode=transport_mode,
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def _request(
    server: bridge.LocalV3BridgeServer,
    method: str,
    path: str,
    body: dict | None = None,
) -> tuple[int, dict]:
    encoded = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        f"http://127.0.0.1:{server.server_port}{path}",
        data=encoded,
        method=method,
        headers={
            "Authorization": "Bearer local-test-token",
            "Content-Type": "application/json",
        },
    )
    try:
        response = urllib.request.urlopen(request, timeout=5)
    except urllib.error.HTTPError as error:
        with error:
            return error.code, json.loads(error.read().decode("utf-8"))
    with response:
        return response.status, json.loads(response.read().decode("utf-8"))


class LocalV3BridgeTests(unittest.TestCase):
    def test_long_transport_uses_rest_adapter_and_105_second_ceiling(self) -> None:
        body = profiler.scenarios()["small"]
        with _running_server(transport_mode="long") as server, redirect_stdout(
            StringIO()
        ):
            status, response = _request(
                server,
                "POST",
                "/v1/llm/v3/responses",
                body,
            )
            health_status, health = _request(server, "GET", "/_local/health")

        self.assertEqual(status, 200)
        self.assertEqual(response["schema_version"], "v3_plan_response_server_v1")
        self.assertEqual(health_status, 200)
        self.assertEqual(health["transport_mode"], "long")
        self.assertEqual(health["provider_timeout_seconds"], 105)
        self.assertEqual(health["lambda_timeout_seconds"], 115)
        self.assertEqual(health["request_count"], 1)
        self.assertEqual(health["provider_attempt_count"], 1)
        self.assertEqual(health["usage_reserve_count"], 1)
        self.assertEqual(health["usage_finalize_count"], 1)
        self.assertEqual(health["usage_release_count"], 0)
        self.assertEqual(server.backend.providers[-1].timeout_seconds, [105])
        self.assertEqual(server.bridge_records[-1]["transport_mode"], "long")

    def test_transport_modes_enforce_separate_provider_ceilings(self) -> None:
        with self.assertRaisesRegex(ValueError, "27 for standard mode"):
            bridge.create_server(port=0, provider_timeout_seconds=28)
        with self.assertRaisesRegex(ValueError, "105 for long mode"):
            bridge.create_server(
                port=0,
                provider_timeout_seconds=106,
                transport_mode="long",
            )

    def test_long_transport_timeout_is_controlled_and_releases_once(self) -> None:
        body = profiler.scenarios()["small"]
        with _running_server(
            scenario="timeout",
            transport_mode="long",
        ) as server, redirect_stdout(StringIO()):
            status, response = _request(
                server,
                "POST",
                "/v1/llm/v3/responses",
                body,
            )

        self.assertEqual(status, 504)
        self.assertEqual(response["error"]["code"], "v3_upstream_timeout")
        self.assertEqual(server.backend.providers[-1].attempt_count, 1)
        self.assertEqual(server.backend.providers[-1].timeout_seconds, [105])
        self.assertEqual(server.backend.usage.reserve_count, 1)
        self.assertEqual(server.backend.usage.finalize_count, 0)
        self.assertEqual(server.backend.usage.release_count, 1)

    def test_live_measurement_runner_is_fixed_to_three_synthetic_calls(self) -> None:
        calls: list[tuple[str, str]] = []

        def fake_measure(*, name: str, body: dict, api_key: str) -> dict:
            del body
            calls.append((name, api_key))
            return {"scenario": name, "status_code": 200}

        with (
            patch.object(
                live_measurement,
                "_load_configured_api_key",
                return_value="PRIVATE_TEST_KEY",
            ),
            patch.object(live_measurement, "_measure", side_effect=fake_measure),
        ):
            report = live_measurement.run()

        self.assertEqual(
            [name for name, _ in calls],
            ["small", "medium", "product_max"],
        )
        self.assertEqual(report["request_count"], 3)
        self.assertNotIn("PRIVATE_TEST_KEY", json.dumps(report))

    def test_product_max_crosses_real_loopback_and_exports_safe_measurement(self) -> None:
        body = profiler.scenarios()["product_max"]
        output = StringIO()
        with _running_server() as server, redirect_stdout(output):
            health_status, health = _request(server, "GET", "/_local/health")
            status, response = _request(
                server,
                "POST",
                "/v1/llm/v3/responses",
                body,
            )
            export_status, export = _request(
                server,
                "GET",
                "/_local/cloudwatch-export",
            )

        self.assertEqual(health_status, 200)
        self.assertEqual(health["transport_mode"], "standard")
        self.assertEqual(health["provider_timeout_seconds"], 27)
        self.assertEqual(health["lambda_timeout_seconds"], 29)
        self.assertEqual(health["network_mode"], "loopback_only")
        self.assertEqual(health["provider_mode"], "deterministic_fake")
        self.assertEqual(status, 200)
        self.assertEqual(response["schema_version"], "v3_plan_response_server_v1")
        self.assertEqual(export_status, 200)
        records = export["results"]
        self.assertEqual(len(records), 1)
        measurement = {
            cell["field"]: cell["value"]
            for cell in records[0]
        }
        self.assertEqual(measurement["v3_row_count"], "32")
        self.assertEqual(measurement["v3_clip_count"], "128")
        self.assertEqual(measurement["v3_group_count"], "16")
        self.assertEqual(measurement["v3_library_asset_count"], "250")
        self.assertNotIn("prompt_trace_id", measurement)
        for forbidden in analyzer.FORBIDDEN_FIELDS:
            self.assertNotIn(forbidden, measurement)
        report = analyzer.analyze([measurement])
        self.assertEqual(report["cohort"]["eligible_backend_count"], 1)
        self.assertEqual(report["decision"]["recommendations"], ["collect_more_data"])
        self.assertEqual(server.backend.usage.finalize_count, 1)
        self.assertEqual(server.backend.usage.release_count, 0)
        self.assertEqual(len(server.bridge_records), 1)
        self.assertIn("Local V3 bridge request complete", output.getvalue())

    def test_dynamic_request_above_legacy_limit_crosses_loopback(self) -> None:
        body = profiler.scenarios()["large_project"]
        encoded_bytes = len(json.dumps(body).encode("utf-8"))
        self.assertGreater(encoded_bytes, bridge.v3_server_contract.MAX_REQUEST_BYTES)
        self.assertLessEqual(
            encoded_bytes,
            bridge.v3_server_contract.DYNAMIC_MAX_REQUEST_BYTES,
        )

        with _running_server() as server, redirect_stdout(StringIO()):
            status, response = _request(
                server,
                "POST",
                "/v1/llm/v3/responses",
                body,
            )

        self.assertEqual(status, 200)
        self.assertEqual(response["schema_version"], "v3_plan_response_server_v1")
        self.assertEqual(len(server.measurements), 1)
        self.assertEqual(server.backend.providers[-1].attempt_count, 1)

    def test_failure_and_repair_scenarios_preserve_status_and_settlement(self) -> None:
        expected = {
            "timeout": (504, "v3_upstream_timeout", 1, False),
            "upstream_error": (500, "v3_upstream_error", 1, False),
            "invalid_output": (502, "v3_invalid_provider_output", 1, False),
            "semantic_repair_success": (200, "", 2, True),
            "semantic_repair_failure": (502, "v3_invalid_provider_output", 2, False),
        }
        body = profiler.scenarios()["small"]
        for scenario, (expected_status, error_code, attempts, finalized) in expected.items():
            with self.subTest(scenario=scenario), _running_server(
                scenario=scenario
            ) as server, redirect_stdout(StringIO()):
                status, response = _request(
                    server,
                    "POST",
                    "/v1/llm/v3/responses",
                    body,
                )
                self.assertEqual(status, expected_status)
                if error_code:
                    self.assertEqual(response["error"]["code"], error_code)
                provider = server.backend.providers[-1]
                self.assertEqual(provider.attempt_count, attempts)
                measurement = server.measurements[-1]
                self.assertEqual(measurement["provider_attempt_count"], attempts)
                self.assertEqual(server.backend.usage.finalize_count, int(finalized))
                self.assertEqual(server.backend.usage.release_count, int(not finalized))
                if scenario.startswith("semantic_repair"):
                    self.assertTrue(measurement["semantic_repair_attempted"])
                    self.assertEqual(
                        measurement["semantic_repair_succeeded"],
                        finalized,
                    )

    def test_delay_is_measured_without_external_provider_calls(self) -> None:
        body = profiler.scenarios()["small"]
        with _running_server(delay_ms=25) as server, redirect_stdout(StringIO()):
            status, _ = _request(
                server,
                "POST",
                "/v1/llm/v3/responses",
                body,
            )
        self.assertEqual(status, 200)
        self.assertGreaterEqual(
            server.measurements[-1]["provider_roundtrip_ms"],
            20,
        )
        self.assertGreaterEqual(server.bridge_records[-1]["bridge_total_ms"], 20)
        self.assertEqual(server.backend.providers[-1].name, "local-deterministic-provider")

    def test_bridge_logs_and_exports_measurements_without_private_content(self) -> None:
        body = json.loads(json.dumps(profiler.scenarios()["small"]))
        markers = (
            "PRIVATE_LOCAL_REQUEST_77C",
            "PRIVATE_LOCAL_PROJECT_14B",
            "PRIVATE_LOCAL_CONTEXT_92F",
            "PRIVATE_LOCAL_TRACE_31A",
        )
        body["original_request"] = markers[0]
        body["project_id"] = markers[1]
        body["core_context"]["project"]["project_id"] = markers[1]
        body["core_context"]["project"]["private_note"] = markers[2]
        body["prompt_trace_id"] = markers[3]
        output = StringIO()
        with _running_server() as server, redirect_stdout(output):
            status, _ = _request(
                server,
                "POST",
                "/v1/llm/v3/responses",
                body,
            )
            _, export = _request(server, "GET", "/_local/cloudwatch-export")
        self.assertEqual(status, 200)
        serialized = json.dumps(export) + output.getvalue()
        for marker in markers:
            self.assertNotIn(marker, serialized)
        provider_state = json.dumps(server.backend.providers[-1].__dict__)
        for marker in markers:
            self.assertNotIn(marker, provider_state)

    def test_bridge_rejects_non_v3_routes(self) -> None:
        with _running_server() as server, redirect_stdout(StringIO()):
            status, response = _request(server, "POST", "/v1/llm/responses", {})
        self.assertEqual(status, 404)
        self.assertEqual(response["error"], "local_route_not_found")
        self.assertEqual(server.measurements, [])


if __name__ == "__main__":
    unittest.main()
