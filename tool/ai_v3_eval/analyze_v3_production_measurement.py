#!/usr/bin/env python3
"""Analyze privacy-filtered Mixroom V3 production measurements offline.

This tool performs no network calls. It accepts a CloudWatch Logs Insights
GetQueryResults export and, optionally, a privacy-filtered PostHog CSV.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


CONTRACT_VERSION = "mixroom_v3_server_contract_6"
REPORT_SCHEMA_VERSION = "mixroom_v3_production_measurement_v1"

TIMING_FIELDS = (
    "v3_user_context_load_ms",
    "v3_context_validation_ms",
    "v3_provider_request_build_ms",
    "v3_usage_reservation_ms",
    "provider_roundtrip_ms",
    "v3_provider_validation_ms",
    "response_normalize_ms",
    "v3_usage_settlement_ms",
)
SIZE_FIELDS = (
    "v3_original_request_bytes",
    "v3_conversation_bytes",
    "v3_core_context_bytes",
    "v3_instructions_bytes",
    "v3_messages_bytes",
    "v3_tool_schema_bytes",
    "v3_provider_request_bytes",
)
COUNT_FIELDS = (
    "v3_conversation_turn_count",
    "v3_declared_command_type_count",
    "v3_effective_command_type_count",
    "v3_tool_command_variant_count",
    "v3_row_count",
    "v3_clip_count",
    "v3_group_count",
    "v3_library_asset_count",
    "provider_attempt_count",
    "v3_plan_command_count",
)
USAGE_FIELDS = (
    "prompt_tokens",
    "cached_prompt_tokens",
    "completion_tokens",
    "reasoning_tokens",
    "total_tokens",
)
BOOLEAN_FIELDS = (
    "usage_reported",
    "prompt_cache_hit",
    "provider_timed_out",
    "semantic_repair_attempted",
    "semantic_repair_succeeded",
    "semantic_repair_skipped_deadline",
)
BACKEND_ALLOWED_FIELDS = frozenset(
    {
        "@timestamp",
        "@ptr",
        "prompt_trace_id",
        "v3_contract_version",
        "provider",
        "effective_model",
        "runtime_config_fingerprint",
        "status_code",
        "error",
        "failure_stage",
        "semantic_repair_error_code",
        "provider_timeout_seconds",
        "provider_repair_timeout_seconds",
        "latency_ms",
        *TIMING_FIELDS,
        *SIZE_FIELDS,
        *COUNT_FIELDS,
        *USAGE_FIELDS,
        *BOOLEAN_FIELDS,
    }
)
CLIENT_ALLOWED_FIELDS = frozenset(
    {
        "timestamp",
        "event",
        "prompt_trace_id",
        "ai_feature",
        "prompt_cycle_total_ms",
        "error_code",
        "success",
        "app_version",
        "platform",
    }
)
FORBIDDEN_FIELDS = frozenset(
    {
        "@message",
        "user_id",
        "project_id",
        "project_id_hash",
        "request_id",
        "provider_response_id",
        "request",
        "request_body",
        "raw_body",
        "core_context",
        "conversation",
        "instructions",
        "messages",
        "tools",
        "tool_schema",
        "provider_output",
        "provider_response",
        "plan",
        "resources",
    }
)


class UnsafeExportError(ValueError):
    """Raised before analysis when an export contains an unsafe field."""


def _check_fields(fields: Iterable[str], allowed: frozenset[str], source: str) -> None:
    for field in fields:
        if field in FORBIDDEN_FIELDS or field not in allowed:
            raise UnsafeExportError(f"Unsafe or unapproved {source} field: {field}")


def load_cloudwatch_export(path: Path) -> list[dict[str, str]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    results = payload.get("results") if isinstance(payload, dict) else payload
    if not isinstance(results, list):
        raise ValueError("CloudWatch export must contain a 'results' list.")
    records: list[dict[str, str]] = []
    for row in results:
        if isinstance(row, dict):
            record = {str(key): str(value) for key, value in row.items()}
        elif isinstance(row, list):
            record = {}
            for cell in row:
                if not isinstance(cell, dict) or set(cell) != {"field", "value"}:
                    raise ValueError("CloudWatch result cells must contain field/value.")
                field = str(cell["field"])
                if field in record:
                    raise ValueError(f"Duplicate CloudWatch field: {field}")
                record[field] = str(cell["value"])
        else:
            raise ValueError("CloudWatch result rows must be lists or objects.")
        _check_fields(record, BACKEND_ALLOWED_FIELDS, "CloudWatch")
        record.pop("@ptr", None)
        records.append(record)
    return records


def load_posthog_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("PostHog CSV requires a header row.")
        _check_fields(reader.fieldnames, CLIENT_ALLOWED_FIELDS, "PostHog")
        return [dict(row) for row in reader]


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or value is None or value == "":
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) and parsed >= 0 else None


def _integer(value: Any) -> int | None:
    parsed = _number(value)
    if parsed is None or not parsed.is_integer():
        return None
    return int(parsed)


def _boolean(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized in {"true", "1"}:
        return True
    if normalized in {"false", "0"}:
        return False
    return None


def _round(value: float) -> float:
    return round(value, 6)


def _rate(numerator: int, denominator: int) -> float | None:
    return _round(numerator / denominator) if denominator else None


def _percentile(values: Sequence[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(math.ceil(percentile * len(ordered)) - 1, 0)
    return ordered[index]


def _stats(values: Iterable[float]) -> dict[str, int | float | None]:
    materialized = list(values)
    if not materialized:
        return {
            "count": 0,
            "min": None,
            "p50": None,
            "p90": None,
            "p95": None,
            "max": None,
            "mean": None,
        }
    return {
        "count": len(materialized),
        "min": _round(min(materialized)),
        "p50": _round(_percentile(materialized, 0.50) or 0),
        "p90": _round(_percentile(materialized, 0.90) or 0),
        "p95": _round(_percentile(materialized, 0.95) or 0),
        "max": _round(max(materialized)),
        "mean": _round(statistics.fmean(materialized)),
    }


def _field_summary(rows: Sequence[Mapping[str, Any]], field: str) -> dict[str, Any]:
    values = [_number(row.get(field)) for row in rows]
    reported = [value for value in values if value is not None]
    return {
        "reported_count": len(reported),
        "missing_count": len(rows) - len(reported),
        "zero_count": sum(value == 0 for value in reported),
        "statistics": _stats(reported),
    }


def _outcome(row: Mapping[str, Any]) -> str:
    status = int(_number(row.get("status_code")) or 0)
    error = str(row.get("error") or "")
    timed_out = _boolean(row.get("provider_timed_out")) is True
    if timed_out or status == 504 or error == "upstream_timeout":
        return "timeout"
    if 200 <= status < 300:
        return "success"
    if error in {
        "upstream_unavailable",
        "llm_upstream_unavailable",
        "v3_upstream_error",
        "v3_upstream_rate_limited",
    }:
        return "upstream_error"
    if str(row.get("failure_stage") or "").startswith(("provider", "semantic_repair")):
        return "upstream_error"
    if status == 502 and error.startswith("v3_"):
        return "invalid_output"
    return "other_failure"


def _size_bucket(value: float) -> str:
    if value < 25_000:
        return "<25 KB"
    if value < 75_000:
        return "25-75 KB"
    if value < 150_000:
        return "75-150 KB"
    if value <= 300_000:
        return "150-300 KB"
    return ">300 KB"


def _segment(rows: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    outcomes = Counter(str(row["_outcome"]) for row in rows)
    provider = [_number(row.get("provider_roundtrip_ms")) for row in rows]
    return {
        "count": len(rows),
        "success_count": outcomes["success"],
        "timeout_count": outcomes["timeout"],
        "timeout_rate": _rate(outcomes["timeout"], len(rows)),
        "provider_roundtrip_ms": _stats(value for value in provider if value is not None),
    }


def _normalized_backend_rows(
    records: Sequence[Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], Counter[str], Counter[str]]:
    eligible: list[dict[str, Any]] = []
    exclusions: Counter[str] = Counter()
    malformed: Counter[str] = Counter()
    numeric_fields = (
        "status_code",
        "latency_ms",
        "provider_timeout_seconds",
        "provider_repair_timeout_seconds",
        *TIMING_FIELDS,
        *SIZE_FIELDS,
        *COUNT_FIELDS,
        *USAGE_FIELDS,
    )
    for source in records:
        _check_fields(source, BACKEND_ALLOWED_FIELDS, "CloudWatch")
        if source.get("v3_contract_version") != CONTRACT_VERSION:
            exclusions["wrong_or_missing_contract"] += 1
            continue
        if "v3_provider_request_bytes" not in source:
            exclusions["not_provider_bound"] += 1
            continue
        timestamp = _parse_timestamp(source.get("@timestamp"))
        if timestamp is None:
            exclusions["missing_or_malformed_timestamp"] += 1
            continue
        row: dict[str, Any] = dict(source)
        row["_timestamp"] = timestamp
        required_invalid = False
        for field in numeric_fields:
            if field not in source:
                continue
            parsed = _integer(source.get(field))
            if parsed is None:
                malformed[field] += 1
                if field in {"status_code", "latency_ms", "v3_provider_request_bytes"}:
                    required_invalid = True
            else:
                row[field] = parsed
        for field in BOOLEAN_FIELDS:
            if field not in source:
                continue
            parsed = _boolean(source.get(field))
            if parsed is None:
                malformed[field] += 1
                row.pop(field, None)
            else:
                row[field] = parsed
        if required_invalid or any(
            field not in row
            for field in ("status_code", "latency_ms", "v3_provider_request_bytes")
        ):
            exclusions["missing_or_malformed_required_metric"] += 1
            continue
        row["_outcome"] = _outcome(row)
        eligible.append(row)
    return eligible, exclusions, malformed


def _normalized_client_rows(
    records: Sequence[Mapping[str, Any]],
) -> tuple[dict[str, dict[str, Any]], Counter[str], int]:
    candidates: list[dict[str, Any]] = []
    exclusions: Counter[str] = Counter()
    for source in records:
        _check_fields(source, CLIENT_ALLOWED_FIELDS, "PostHog")
        if source.get("event") not in {
            "ai_prompt_cycle_completed",
            "ai_prompt_cycle_failed",
        }:
            exclusions["unrelated_event"] += 1
            continue
        trace = str(source.get("prompt_trace_id") or "").strip()
        timestamp = _parse_timestamp(source.get("timestamp"))
        total = _number(source.get("prompt_cycle_total_ms"))
        if not trace or timestamp is None or total is None:
            exclusions["missing_or_malformed_join_data"] += 1
            continue
        candidates.append({"_trace": trace, "_timestamp": timestamp, "total_ms": total})
    counts = Counter(row["_trace"] for row in candidates)
    duplicate_count = sum(count - 1 for count in counts.values() if count > 1)
    if duplicate_count:
        exclusions["duplicate_prompt_trace"] += duplicate_count
    return (
        {row["_trace"]: row for row in candidates if counts[row["_trace"]] == 1},
        exclusions,
        duplicate_count,
    )


def analyze(
    backend_records: Sequence[Mapping[str, Any]],
    client_records: Sequence[Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    rows, backend_exclusions, malformed = _normalized_backend_rows(backend_records)
    clients, client_exclusions, _ = _normalized_client_rows(client_records or [])
    outcomes = Counter(row["_outcome"] for row in rows)
    successes = [row for row in rows if row["_outcome"] == "success"]
    dates = sorted({row["_timestamp"].date().isoformat() for row in rows})

    backend_by_trace: dict[str, dict[str, Any]] = {}
    duplicate_backend_traces: set[str] = set()
    backend_missing_prompt_trace_count = 0
    for row in rows:
        trace = str(row.get("prompt_trace_id") or "").strip()
        if not trace:
            backend_missing_prompt_trace_count += 1
            continue
        if trace in backend_by_trace:
            duplicate_backend_traces.add(trace)
        else:
            backend_by_trace[trace] = row
    for trace in duplicate_backend_traces:
        backend_by_trace.pop(trace, None)
    matches = [
        (backend_by_trace[trace], client)
        for trace, client in clients.items()
        if trace in backend_by_trace
    ]
    client_total = [client["total_ms"] for _, client in matches]
    client_overhead = [
        client["total_ms"] - backend["latency_ms"]
        for backend, client in matches
        if client["total_ms"] >= backend["latency_ms"]
    ]
    negative_client_overhead_count = sum(
        client["total_ms"] < backend["latency_ms"] for backend, client in matches
    )

    phase_stats = {
        field: _field_summary(rows, field)
        for field in TIMING_FIELDS
    }
    unaccounted: list[float] = []
    provider_shares: list[float] = []
    for row in rows:
        total = row["latency_ms"]
        phase_sum = sum(
            value
            for field in TIMING_FIELDS
            if (value := _number(row.get(field))) is not None
        )
        unaccounted.append(max(total - phase_sum, 0))
        provider = _number(row.get("provider_roundtrip_ms"))
        if total > 0 and provider is not None:
            provider_shares.append(provider / total)

    size_buckets: dict[str, list[dict[str, Any]]] = {
        label: []
        for label in ("<25 KB", "25-75 KB", "75-150 KB", "150-300 KB", ">300 KB")
    }
    cache_segments: dict[str, list[dict[str, Any]]] = {
        "hit": [],
        "miss": [],
        "not_reported": [],
    }
    repair_segments: dict[str, list[dict[str, Any]]] = {
        "repaired": [],
        "unrepaired": [],
    }
    for row in rows:
        size_buckets[_size_bucket(row["v3_provider_request_bytes"])].append(row)
        cache_hit = _boolean(row.get("prompt_cache_hit"))
        cache_segments["not_reported" if cache_hit is None else "hit" if cache_hit else "miss"].append(row)
        repair_segments[
            "repaired" if _boolean(row.get("semantic_repair_attempted")) else "unrepaired"
        ].append(row)

    repair_attempts = repair_segments["repaired"]
    repair_failures = sum(
        _boolean(row.get("semantic_repair_succeeded")) is False
        for row in repair_attempts
    )
    prompt_reported = [
        row for row in rows if _number(row.get("prompt_tokens")) is not None
    ]
    cached_reported = [
        row for row in rows if _number(row.get("cached_prompt_tokens")) is not None
    ]
    prompt_sum = sum(row["prompt_tokens"] for row in prompt_reported)
    cached_sum = sum(row["cached_prompt_tokens"] for row in cached_reported)

    sufficient_backend = len(rows) >= 300 and len(dates) >= 7
    sufficient_client = len(matches) >= 100
    small = [row for row in rows if row["v3_provider_request_bytes"] < 75_000]
    large = [row for row in rows if row["v3_provider_request_bytes"] >= 150_000]
    comparable_sizes = len(small) >= 30 and len(large) >= 30
    small_segment = _segment(small)
    large_segment = _segment(large)
    small_p95 = small_segment["provider_roundtrip_ms"]["p95"]
    large_p95 = large_segment["provider_roundtrip_ms"]["p95"]
    size_latency_signal = (
        comparable_sizes
        and small_p95 is not None
        and large_p95 is not None
        and large_p95 >= small_p95 * 1.25
    )
    small_timeout_rate = small_segment["timeout_rate"]
    large_timeout_rate = large_segment["timeout_rate"]
    size_timeout_signal = (
        comparable_sizes
        and large_segment["timeout_count"] >= 5
        and small_timeout_rate is not None
        and large_timeout_rate is not None
        and (
            (small_timeout_rate == 0 and large_timeout_rate > 0)
            or large_timeout_rate >= small_timeout_rate * 2
        )
    )
    size_signal = bool(size_latency_signal or size_timeout_signal)
    build_p95 = phase_stats["v3_provider_request_build_ms"]["statistics"]["p95"]
    total_p95 = _stats(row["latency_ms"] for row in rows)["p95"]
    build_share_of_total_p95 = (
        build_p95 / total_p95
        if build_p95 is not None and total_p95 not in {None, 0}
        else None
    )
    build_signal = bool(
        (build_p95 is not None and build_p95 >= 500)
        or (
            build_share_of_total_p95 is not None
            and build_share_of_total_p95 >= 0.05
        )
    )
    repair_rate = _rate(len(repair_attempts), len(rows))
    repair_failure_rate = _rate(repair_failures, len(repair_attempts))
    repair_signal = bool(
        len(repair_attempts) >= 5
        and (
            (repair_rate is not None and repair_rate > 0.05)
            or (
                repair_failure_rate is not None
                and repair_failure_rate >= 0.10
            )
        )
    )
    timeout_rate = _rate(outcomes["timeout"], len(rows))
    invalid_rate = _rate(outcomes["invalid_output"], len(rows))
    success_p95 = _stats(row["latency_ms"] for row in successes)["p95"]
    provider_share_p50 = _percentile(provider_shares, 0.50)
    no_change_signal = bool(
        sufficient_backend
        and timeout_rate is not None
        and timeout_rate < 0.01
        and success_p95 is not None
        and success_p95 < 25_000
        and invalid_rate is not None
        and invalid_rate < 0.01
        and not (size_signal or build_signal or repair_signal)
    )
    canary_signal = bool(
        sufficient_backend
        and outcomes["timeout"] >= 5
        and timeout_rate is not None
        and timeout_rate >= 0.02
        and provider_share_p50 is not None
        and provider_share_p50 >= 0.80
        and not (size_signal or build_signal or repair_signal)
    )
    if not sufficient_backend:
        recommendations = ["collect_more_data"]
    else:
        recommendations = []
        if size_signal:
            recommendations.append("consider_schema_or_context_work")
        if build_signal:
            recommendations.append("consider_request_construction_work")
        if repair_signal:
            recommendations.append("consider_first_pass_reliability_work")
        if canary_signal:
            recommendations.append("consider_longer_running_architecture_canary")
        if not recommendations:
            recommendations.append("no_change" if no_change_signal else "mixed_evidence_no_change")

    configurations = {
        field: dict(sorted(Counter(str(row[field]) for row in rows if row.get(field)).items()))
        for field in ("provider", "effective_model", "runtime_config_fingerprint")
    }
    report: dict[str, Any] = {
        "report_schema_version": REPORT_SCHEMA_VERSION,
        "contract_version": CONTRACT_VERSION,
        "cohort": {
            "input_backend_count": len(backend_records),
            "eligible_backend_count": len(rows),
            "input_client_count": len(client_records or []),
            "eligible_unique_client_count": len(clients),
            "first_timestamp": min((row["_timestamp"].isoformat() for row in rows), default=None),
            "last_timestamp": max((row["_timestamp"].isoformat() for row in rows), default=None),
            "calendar_day_count": len(dates),
            "matched_client_count": len(matches),
            "backend_evidence_sufficient": sufficient_backend,
            "client_latency_evidence_sufficient": sufficient_client,
            "size_comparison_sufficient": comparable_sizes,
        },
        "data_quality": {
            "backend_exclusions": dict(sorted(backend_exclusions.items())),
            "client_exclusions": dict(sorted(client_exclusions.items())),
            "malformed_fields": dict(sorted(malformed.items())),
            "duplicate_backend_prompt_traces": len(duplicate_backend_traces),
            "backend_missing_prompt_trace_count": backend_missing_prompt_trace_count,
            "unmatched_backend_count": len(backend_by_trace) - len(matches),
            "unmatched_client_count": len(clients) - len(matches),
            "negative_client_overhead_count": negative_client_overhead_count,
            "field_presence": {
                field: {
                    "reported_count": summary["reported_count"],
                    "missing_count": summary["missing_count"],
                    "zero_count": summary["zero_count"],
                }
                for field in (*TIMING_FIELDS, *SIZE_FIELDS, *COUNT_FIELDS, *USAGE_FIELDS)
                if (summary := _field_summary(rows, field))
            },
        },
        "configurations": configurations,
        "outcomes": {
            label: {"count": outcomes[label], "rate": _rate(outcomes[label], len(rows))}
            for label in ("success", "timeout", "upstream_error", "invalid_output", "other_failure")
        },
        "status_and_errors": {
            "status_codes": dict(
                sorted(Counter(str(int(row["status_code"])) for row in rows).items())
            ),
            "error_codes": dict(
                sorted(Counter(str(row["error"]) for row in rows if row.get("error")).items())
            ),
        },
        "latency_ms": {
            "total": _stats(row["latency_ms"] for row in rows),
            "successful_total": _stats(row["latency_ms"] for row in successes),
            "phases": phase_stats,
            "unaccounted": _stats(unaccounted),
            "provider_share": _stats(provider_shares),
            "client_prompt_cycle": _stats(client_total),
            "client_minus_backend": _stats(client_overhead),
        },
        "sizes_bytes": {field: _field_summary(rows, field) for field in SIZE_FIELDS},
        "counts": {field: _field_summary(rows, field) for field in COUNT_FIELDS},
        "usage": {
            **{field: _field_summary(rows, field) for field in USAGE_FIELDS},
            "cache_hit_rate": _rate(len(cache_segments["hit"]), len(cache_segments["hit"]) + len(cache_segments["miss"])),
            "cached_input_token_ratio": _round(cached_sum / prompt_sum) if prompt_sum else None,
        },
        "repairs": {
            "attempt_count": len(repair_attempts),
            "attempt_rate": repair_rate,
            "failure_count": repair_failures,
            "failure_rate": repair_failure_rate,
        },
        "segments": {
            "provider_request_size": {label: _segment(segment) for label, segment in size_buckets.items()},
            "cache": {label: _segment(segment) for label, segment in cache_segments.items()},
            "repair": {label: _segment(segment) for label, segment in repair_segments.items()},
            "size_gate_comparison": {"small_below_75_kb": small_segment, "large_at_least_150_kb": large_segment},
        },
        "decision": {
            "gate_metrics": {
                "timeout_count": outcomes["timeout"],
                "timeout_rate": timeout_rate,
                "invalid_output_rate": invalid_rate,
                "successful_total_p95_ms": success_p95,
                "small_request_count": len(small),
                "large_request_count": len(large),
                "small_provider_p95_ms": small_p95,
                "large_provider_p95_ms": large_p95,
                "small_timeout_rate": small_timeout_rate,
                "large_timeout_rate": large_timeout_rate,
                "request_build_p95_ms": build_p95,
                "request_build_share_of_total_p95": (
                    _round(build_share_of_total_p95)
                    if build_share_of_total_p95 is not None
                    else None
                ),
                "repair_attempt_count": len(repair_attempts),
                "repair_attempt_rate": repair_rate,
                "repair_failure_count": repair_failures,
                "repair_failure_rate": repair_failure_rate,
                "provider_share_p50": (
                    _round(provider_share_p50)
                    if provider_share_p50 is not None
                    else None
                ),
            },
            "signals": {
                "schema_or_context": size_signal,
                "request_construction": build_signal,
                "first_pass_reliability": repair_signal,
                "longer_running_architecture_canary": canary_signal,
                "no_change": no_change_signal,
            },
            "recommendations": recommendations,
            "automatic_code_changes": False,
        },
    }
    return report


def render_markdown(report: Mapping[str, Any]) -> str:
    cohort = report["cohort"]
    outcomes = report["outcomes"]
    total = report["latency_ms"]["total"]
    success = report["latency_ms"]["successful_total"]
    phases = report["latency_ms"]["phases"]
    sizes = report["sizes_bytes"]
    usage = report["usage"]
    repairs = report["repairs"]
    size_segments = report["segments"]["provider_request_size"]
    gate_metrics = report["decision"]["gate_metrics"]
    lines = [
        "# Mixroom V3 production measurement",
        "",
        "## Cohort",
        "",
        f"- Eligible backend requests: {cohort['eligible_backend_count']}",
        f"- Calendar days: {cohort['calendar_day_count']}",
        f"- Matched client events: {cohort['matched_client_count']}",
        f"- Backend evidence sufficient: {str(cohort['backend_evidence_sufficient']).lower()}",
        f"- Client latency evidence sufficient: {str(cohort['client_latency_evidence_sufficient']).lower()}",
        "",
        "## Outcomes",
        "",
    ]
    for label in ("success", "timeout", "upstream_error", "invalid_output", "other_failure"):
        value = outcomes[label]
        lines.append(f"- {label}: {value['count']} ({value['rate']})")
    lines.extend(
        [
            "",
            "## Latency",
            "",
            f"- Total p50/p90/p95/max ms: {total['p50']} / {total['p90']} / {total['p95']} / {total['max']}",
            f"- Successful p95 ms: {success['p95']}",
            f"- Unaccounted p95 ms: {report['latency_ms']['unaccounted']['p95']}",
            f"- Provider share p50: {gate_metrics['provider_share_p50']}",
            "",
            "| Phase | Reported | Missing | p50 ms | p95 ms |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for field in TIMING_FIELDS:
        phase = phases[field]
        stats = phase["statistics"]
        lines.append(
            f"| `{field}` | {phase['reported_count']} | {phase['missing_count']} | {stats['p50']} | {stats['p95']} |"
        )
    lines.extend(
        [
            "",
            "## Request size",
            "",
            "| Component | Reported | Missing | p50 bytes | p95 bytes |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for field in SIZE_FIELDS:
        component = sizes[field]
        stats = component["statistics"]
        lines.append(
            f"| `{field}` | {component['reported_count']} | {component['missing_count']} | {stats['p50']} | {stats['p95']} |"
        )
    lines.extend(
        [
            "",
            "| Provider request segment | Count | Timeout rate | Provider p95 ms |",
            "| --- | ---: | ---: | ---: |",
        ]
    )
    for label in ("<25 KB", "25-75 KB", "75-150 KB", "150-300 KB", ">300 KB"):
        segment = size_segments[label]
        lines.append(
            f"| {label} | {segment['count']} | {segment['timeout_rate']} | {segment['provider_roundtrip_ms']['p95']} |"
        )
    lines.extend(
        [
            "",
            "## Usage and reliability",
            "",
            f"- Input tokens p50/p95: {usage['prompt_tokens']['statistics']['p50']} / {usage['prompt_tokens']['statistics']['p95']}",
            f"- Cached-input tokens p50/p95: {usage['cached_prompt_tokens']['statistics']['p50']} / {usage['cached_prompt_tokens']['statistics']['p95']}",
            f"- Output tokens p50/p95: {usage['completion_tokens']['statistics']['p50']} / {usage['completion_tokens']['statistics']['p95']}",
            f"- Reasoning tokens p50/p95: {usage['reasoning_tokens']['statistics']['p50']} / {usage['reasoning_tokens']['statistics']['p95']}",
            f"- Cache hit rate: {usage['cache_hit_rate']}",
            f"- Cached-input token ratio: {usage['cached_input_token_ratio']}",
            f"- Repair attempts: {repairs['attempt_count']} ({repairs['attempt_rate']})",
            f"- Failed repairs: {repairs['failure_count']} ({repairs['failure_rate']})",
            "",
            "## Decision",
            "",
        ]
    )
    lines.extend(f"- {item}" for item in report["decision"]["recommendations"])
    lines.extend(["", "No code or infrastructure changes are made by this report.", ""])
    return "\n".join(lines)


def canonical_json(report: Mapping[str, Any]) -> str:
    return json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cloudwatch-results",
        type=Path,
        action="append",
        required=True,
        help="CloudWatch export path; repeat for non-overlapping query windows.",
    )
    parser.add_argument("--posthog-csv", type=Path)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-markdown", type=Path)
    args = parser.parse_args()
    backend = [
        record
        for path in args.cloudwatch_results
        for record in load_cloudwatch_export(path)
    ]
    clients = load_posthog_csv(args.posthog_csv) if args.posthog_csv else None
    report = analyze(backend, clients)
    encoded = canonical_json(report)
    if args.output_json:
        args.output_json.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    if args.output_markdown:
        args.output_markdown.write_text(render_markdown(report), encoding="utf-8")


if __name__ == "__main__":
    main()
