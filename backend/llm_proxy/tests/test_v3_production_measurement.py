from __future__ import annotations

import csv
import importlib.util
import json
import random
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ANALYZER_PATH = (
    ROOT / "tool" / "ai_v3_eval" / "analyze_v3_production_measurement.py"
)
SPEC = importlib.util.spec_from_file_location(
    "analyze_v3_production_measurement",
    ANALYZER_PATH,
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load the V3 production measurement analyzer.")
analyzer = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = analyzer
SPEC.loader.exec_module(analyzer)


def _backend_record(
    index: int,
    *,
    size: int = 50_000,
    latency_ms: int = 10_000,
    provider_ms: int = 9_000,
    build_ms: int = 20,
    status: int = 200,
    error: str = "",
    timed_out: bool = False,
    repaired: bool = False,
    repair_succeeded: bool | None = None,
) -> dict[str, object]:
    timestamp = datetime(2026, 8, 1, tzinfo=timezone.utc) + timedelta(
        days=index % 7,
        seconds=index,
    )
    record: dict[str, object] = {
        "@timestamp": timestamp.isoformat(),
        "prompt_trace_id": f"trace-{index:04d}",
        "v3_contract_version": analyzer.CONTRACT_VERSION,
        "provider": "openai",
        "effective_model": "synthetic-model",
        "runtime_config_fingerprint": "synthetic-fingerprint",
        "status_code": status,
        "latency_ms": latency_ms,
        "error": error,
        "provider_timed_out": timed_out,
        "v3_context_validation_ms": 2,
        "v3_provider_request_build_ms": build_ms,
        "v3_usage_reservation_ms": 3,
        "provider_roundtrip_ms": provider_ms,
        "v3_provider_validation_ms": 4,
        "response_normalize_ms": 5,
        "v3_usage_settlement_ms": 3,
        "v3_original_request_bytes": 50,
        "v3_conversation_bytes": 100,
        "v3_core_context_bytes": 5_000,
        "v3_instructions_bytes": 6_000,
        "v3_messages_bytes": 7_000,
        "v3_tool_schema_bytes": 30_000,
        "v3_provider_request_bytes": size,
        "v3_conversation_turn_count": 2,
        "v3_declared_command_type_count": 54,
        "v3_effective_command_type_count": 54,
        "v3_tool_command_variant_count": 54,
        "v3_row_count": 8,
        "v3_clip_count": 16,
        "v3_group_count": 4,
        "v3_library_asset_count": 16,
        "provider_attempt_count": 2 if repaired else 1,
        "v3_plan_command_count": 3,
        "usage_reported": True,
        "prompt_tokens": 10_000,
        "cached_prompt_tokens": 0,
        "prompt_cache_hit": False,
        "completion_tokens": 500,
        "reasoning_tokens": 0,
        "total_tokens": 10_500,
        "semantic_repair_attempted": repaired,
    }
    if repair_succeeded is not None:
        record["semantic_repair_succeeded"] = repair_succeeded
    return record


def _client_record(index: int, *, matched: bool = True) -> dict[str, object]:
    timestamp = datetime(2026, 8, 1, tzinfo=timezone.utc) + timedelta(
        days=index % 7,
        seconds=index,
    )
    return {
        "timestamp": timestamp.isoformat(),
        "event": "ai_prompt_cycle_completed",
        "prompt_trace_id": f"trace-{index:04d}" if matched else f"other-{index:04d}",
        "ai_feature": "mixroom_v3",
        "prompt_cycle_total_ms": 10_250,
        "error_code": "",
        "success": True,
        "app_version": "synthetic",
        "platform": "test",
    }


class V3ProductionMeasurementTests(unittest.TestCase):
    def test_cloudwatch_loader_accepts_selected_fields_and_rejects_secrets(self) -> None:
        safe_record = _backend_record(0)
        cloudwatch_row = [
            {"field": key, "value": str(value).lower() if isinstance(value, bool) else str(value)}
            for key, value in safe_record.items()
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cloudwatch.json"
            path.write_text(json.dumps({"results": [cloudwatch_row]}), encoding="utf-8")
            loaded = analyzer.load_cloudwatch_export(path)
            self.assertEqual(len(loaded), 1)

            for field in (
                "@message",
                "user_id",
                "project_id",
                "request_body",
                "core_context",
                "provider_output",
            ):
                marker = f"UNIQUE_PRIVATE_MARKER_{field}_6F441"
                unsafe = cloudwatch_row + [{"field": field, "value": marker}]
                path.write_text(json.dumps({"results": [unsafe]}), encoding="utf-8")
                with self.subTest(field=field), self.assertRaises(
                    analyzer.UnsafeExportError
                ) as raised:
                    analyzer.load_cloudwatch_export(path)
                self.assertNotIn(marker, str(raised.exception))

    def test_posthog_loader_rejects_unapproved_columns_without_echoing_values(self) -> None:
        marker = "UNIQUE_PROJECT_MARKER_A9831"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "posthog.csv"
            with path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(
                    handle,
                    fieldnames=["timestamp", "event", "prompt_trace_id", "project_id"],
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "timestamp": "2026-08-01T00:00:00Z",
                        "event": "ai_prompt_cycle_completed",
                        "prompt_trace_id": "join-only",
                        "project_id": marker,
                    }
                )
            with self.assertRaises(analyzer.UnsafeExportError) as raised:
                analyzer.load_posthog_csv(path)
            self.assertNotIn(marker, str(raised.exception))

    def test_deterministic_report_preserves_missing_vs_zero_and_joins_in_memory(self) -> None:
        backend = [_backend_record(index) for index in range(300)]
        for record in backend[:10]:
            record.pop("reasoning_tokens")
        backend[10]["completion_tokens"] = "malformed"
        clients = [_client_record(index) for index in range(100)]
        clients.extend(_client_record(index + 300, matched=False) for index in range(5))
        shuffled_backend = list(backend)
        shuffled_clients = list(clients)
        random.Random(17).shuffle(shuffled_backend)
        random.Random(29).shuffle(shuffled_clients)

        first = analyzer.analyze(backend, clients)
        second = analyzer.analyze(shuffled_backend, shuffled_clients)
        self.assertEqual(analyzer.canonical_json(first), analyzer.canonical_json(second))
        reasoning = first["usage"]["reasoning_tokens"]
        self.assertEqual(reasoning["reported_count"], 290)
        self.assertEqual(reasoning["missing_count"], 10)
        self.assertEqual(reasoning["zero_count"], 290)
        self.assertEqual(first["data_quality"]["malformed_fields"]["completion_tokens"], 1)
        self.assertEqual(first["cohort"]["matched_client_count"], 100)
        self.assertEqual(first["data_quality"]["unmatched_client_count"], 5)
        self.assertEqual(first["data_quality"]["unmatched_backend_count"], 200)
        self.assertTrue(first["cohort"]["client_latency_evidence_sufficient"])
        encoded = analyzer.canonical_json(first)
        markdown = analyzer.render_markdown(first)
        self.assertNotIn("trace-0000", encoded)
        self.assertNotIn("trace-0000", markdown)

    def test_outcomes_cache_and_repair_groups_are_classified(self) -> None:
        records = [
            _backend_record(0),
            _backend_record(1, status=504, error="upstream_timeout", timed_out=True),
            _backend_record(2, status=502, error="v3_upstream_error"),
            _backend_record(3, status=502, error="v3_invalid_provider_output"),
            _backend_record(4, status=400, error="bad_request"),
        ]
        records[0]["cached_prompt_tokens"] = 500
        records[0]["prompt_cache_hit"] = True
        records[3]["semantic_repair_attempted"] = True
        records[3]["semantic_repair_succeeded"] = False
        report = analyzer.analyze(records)
        for outcome in (
            "success",
            "timeout",
            "upstream_error",
            "invalid_output",
            "other_failure",
        ):
            self.assertEqual(report["outcomes"][outcome]["count"], 1)
        self.assertEqual(report["segments"]["cache"]["hit"]["count"], 1)
        self.assertEqual(report["segments"]["cache"]["miss"]["count"], 4)
        self.assertEqual(report["repairs"]["attempt_count"], 1)
        self.assertEqual(report["repairs"]["failure_count"], 1)

    def test_size_bucket_boundaries_are_stable(self) -> None:
        records = [
            _backend_record(0, size=24_999),
            _backend_record(1, size=25_000),
            _backend_record(2, size=75_000),
            _backend_record(3, size=150_000),
            _backend_record(4, size=300_001),
        ]
        segments = analyzer.analyze(records)["segments"]["provider_request_size"]
        self.assertEqual(segments["<25 KB"]["count"], 1)
        self.assertEqual(segments["25-75 KB"]["count"], 1)
        self.assertEqual(segments["75-150 KB"]["count"], 1)
        self.assertEqual(segments["150-300 KB"]["count"], 1)
        self.assertEqual(segments[">300 KB"]["count"], 1)

    def test_insufficient_evidence_only_collects_more_data(self) -> None:
        report = analyzer.analyze([_backend_record(index) for index in range(299)])
        self.assertEqual(report["decision"]["recommendations"], ["collect_more_data"])
        self.assertFalse(report["cohort"]["backend_evidence_sufficient"])

    def test_no_change_gate(self) -> None:
        report = analyzer.analyze([_backend_record(index) for index in range(300)])
        self.assertTrue(report["decision"]["signals"]["no_change"])
        self.assertEqual(report["decision"]["recommendations"], ["no_change"])

    def test_schema_or_context_gate(self) -> None:
        records = [
            _backend_record(index, size=50_000, provider_ms=8_000)
            for index in range(150)
        ] + [
            _backend_record(index + 150, size=200_000, latency_ms=13_000, provider_ms=11_000)
            for index in range(150)
        ]
        report = analyzer.analyze(records)
        self.assertTrue(report["cohort"]["size_comparison_sufficient"])
        self.assertTrue(report["decision"]["signals"]["schema_or_context"])
        self.assertIn("consider_schema_or_context_work", report["decision"]["recommendations"])

    def test_schema_or_context_timeout_ratio_gate(self) -> None:
        records = [
            _backend_record(index, size=50_000)
            for index in range(150)
        ] + [
            _backend_record(index + 150, size=200_000)
            for index in range(150)
        ]
        records[0] = _backend_record(
            0,
            size=50_000,
            status=504,
            error="upstream_timeout",
            timed_out=True,
        )
        for index in range(150, 155):
            records[index] = _backend_record(
                index,
                size=200_000,
                status=504,
                error="upstream_timeout",
                timed_out=True,
            )
        report = analyzer.analyze(records)
        self.assertTrue(report["decision"]["signals"]["schema_or_context"])

    def test_request_construction_gate(self) -> None:
        records = [_backend_record(index, build_ms=600) for index in range(300)]
        report = analyzer.analyze(records)
        self.assertTrue(report["decision"]["signals"]["request_construction"])
        self.assertIn("consider_request_construction_work", report["decision"]["recommendations"])

    def test_request_construction_five_percent_gate(self) -> None:
        records = [
            _backend_record(index, latency_ms=9_000, provider_ms=8_000, build_ms=499)
            for index in range(300)
        ]
        report = analyzer.analyze(records)
        self.assertTrue(report["decision"]["signals"]["request_construction"])
        self.assertLess(report["decision"]["gate_metrics"]["request_build_p95_ms"], 500)

    def test_repair_rate_and_failed_repair_gates(self) -> None:
        repair_rate_records = [_backend_record(index) for index in range(300)]
        for index in range(20):
            repair_rate_records[index] = _backend_record(
                index,
                repaired=True,
                repair_succeeded=True,
            )
        failed_repair_records = [_backend_record(index) for index in range(300)]
        for index in range(5):
            failed_repair_records[index] = _backend_record(
                index,
                repaired=True,
                repair_succeeded=index != 0,
            )
        for records in (repair_rate_records, failed_repair_records):
            with self.subTest(repairs=sum(bool(row.get("semantic_repair_attempted")) for row in records)):
                report = analyzer.analyze(records)
                self.assertTrue(report["decision"]["signals"]["first_pass_reliability"])
                self.assertIn("consider_first_pass_reliability_work", report["decision"]["recommendations"])

        fewer_than_five = [_backend_record(index) for index in range(300)]
        for index in range(4):
            fewer_than_five[index] = _backend_record(
                index,
                repaired=True,
                repair_succeeded=False,
            )
        report = analyzer.analyze(fewer_than_five)
        self.assertFalse(report["decision"]["signals"]["first_pass_reliability"])

    def test_longer_running_architecture_canary_gate(self) -> None:
        records = [_backend_record(index) for index in range(300)]
        for index in range(10):
            records[index] = _backend_record(
                index,
                status=504,
                error="upstream_timeout",
                timed_out=True,
            )
        report = analyzer.analyze(records)
        self.assertTrue(
            report["decision"]["signals"]["longer_running_architecture_canary"]
        )
        self.assertIn(
            "consider_longer_running_architecture_canary",
            report["decision"]["recommendations"],
        )
        self.assertFalse(report["decision"]["automatic_code_changes"])

        for index in range(300):
            records[index]["v3_provider_request_build_ms"] = 600
        safer_local_signal = analyzer.analyze(records)
        self.assertTrue(
            safer_local_signal["decision"]["signals"]["request_construction"]
        )
        self.assertFalse(
            safer_local_signal["decision"]["signals"][
                "longer_running_architecture_canary"
            ]
        )


if __name__ == "__main__":
    unittest.main()
