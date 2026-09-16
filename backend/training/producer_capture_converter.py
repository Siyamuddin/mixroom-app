#!/usr/bin/env python3
"""Convert producer capture v4 bundles into sharded model-training JSONL."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
import tempfile
from datetime import datetime, timezone
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator
from urllib.parse import urlparse

BACKEND_ROOT = Path(__file__).resolve().parents[1]
LLM_PROXY_SRC = BACKEND_ROOT / "llm_proxy" / "src"
if str(LLM_PROXY_SRC) not in sys.path:
    sys.path.insert(0, str(LLM_PROXY_SRC))

from common.mix_resolve import MixResolveService, contract_version  # noqa: E402
from common.mix_plugin_contract import CONTRACT as PLUGIN_CONTRACT, extra_features, plugin_supervision, bus_target, chain, parameter_target, PARAM_ACTIONS, parameter_recreated

CAPTURE_SCHEMA = "producer_training_capture_v4"
DATASET_SCHEMA = "producer_training_examples_v2"
SUPPORTED_MODEL_ACTIONS = frozenset(
    {
        "set_row_gain",
        "set_row_pan",
        "set_master_gain",
        "set_master_pan",
        "adjust_effect_param_by_name",
        "adjust_master_effect_param_by_name",
        "ensure_effect",
        "ensure_master_effect",
        "delete_effect",
        "delete_master_effect",
        "hard_reset_row_fx",
        "hard_reset_master_fx",
    }
)


class ConversionError(ValueError):
    pass


@dataclass
class ConversionStats:
    bundles_seen: int = 0
    bundles_converted: int = 0
    episodes_seen: int = 0
    examples_written: int = 0
    errors: Counter[str] = field(default_factory=Counter)
    objectives: Counter[str] = field(default_factory=Counter)
    splits: Counter[str] = field(default_factory=Counter)
    action_types: Counter[str] = field(default_factory=Counter)
    exclusions: Counter[str] = field(default_factory=Counter)

    def manifest(self, *, shards: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "dataset_schema_version": DATASET_SCHEMA,
            "source_schema_version": CAPTURE_SCHEMA,
            "mix_feature_contract_version": contract_version(),
            "feature_count": 77,
            "plugin_feature_contract_version": PLUGIN_CONTRACT,
            "plugin_feature_count": 64,
            "bundles_seen": self.bundles_seen,
            "bundles_converted": self.bundles_converted,
            "episodes_seen": self.episodes_seen,
            "examples_written": self.examples_written,
            "errors": dict(sorted(self.errors.items())),
            "objective_example_counts": dict(sorted(self.objectives.items())),
            "split_counts": dict(sorted(self.splits.items())),
            "action_type_counts": dict(sorted(self.action_types.items())),
            "exclusion_reason_counts": dict(sorted(self.exclusions.items())),
            "shards": shards,
        }


class JsonlShardWriter:
    def __init__(self, directory: Path, shard_size: int, *, prefix: str = "examples") -> None:
        self.directory = directory
        self.prefix = prefix
        self.shard_size = max(1, shard_size)
        self.directory.mkdir(parents=True, exist_ok=True)
        self._handle = None
        self._count = 0
        self._shard_count = 0
        self.shards: list[dict[str, Any]] = []

    def write(self, example: dict[str, Any]) -> None:
        if self._handle is None or self._count >= self.shard_size:
            self._open_next()
        assert self._handle is not None
        self._handle.write(json.dumps(example, sort_keys=True, separators=(",", ":")))
        self._handle.write("\n")
        self._count += 1
        self.shards[-1]["examples"] = self._count

    def _open_next(self) -> None:
        self.close_handle()
        name = f"{self.prefix}-{self._shard_count:05d}.jsonl"
        self._shard_count += 1
        self._count = 0
        self._handle = (self.directory / name).open("w", encoding="utf-8")
        self.shards.append({"name": name, "examples": 0})

    def close_handle(self) -> None:
        if self._handle is not None:
            self._handle.close()
            self._handle = None

    def finish(self) -> None:
        self.close_handle()
        for shard in self.shards:
            path = self.directory / shard["name"]
            shard["bytes"] = path.stat().st_size
            shard["sha256"] = _sha256(path.read_bytes())


def _sha256(value: bytes | str) -> str:
    raw = value.encode("utf-8") if isinstance(value, str) else value
    return hashlib.sha256(raw).hexdigest()


def _mapping(value: Any) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def _first_number(values: Iterable[Any]) -> float | None:
    for value in values:
        parsed = _number(value)
        if parsed is not None:
            return parsed
    return None


def _project(episode: dict[str, Any]) -> dict[str, Any]:
    before = _mapping(episode.get("state_before"))
    project = _mapping(before.get("project_state"))
    if not isinstance(project.get("rows"), list):
        raise ConversionError("missing_project_state")
    return project


def _effect_name(project: dict[str, Any], *, row: int | None, index: int, master: bool) -> str:
    effects: Any = project.get("master_effects") if master else None
    if not master:
        rows = project.get("rows") or []
        target = next(
            (
                candidate
                for candidate in rows
                if isinstance(candidate, dict)
                and int(candidate.get("row", -1)) == row
            ),
            None,
        )
        effects = target.get("effects") if isinstance(target, dict) else None
    if isinstance(effects, list) and 0 <= index < len(effects):
        effect = effects[index]
        if isinstance(effect, dict):
            return str(effect.get("name") or effect.get("effectId") or "").strip()
    return ""


def _manual_action(raw: dict[str, Any], project: dict[str, Any]) -> dict[str, Any] | None:
    kind = str(raw.get("kind") or "").strip().lower()
    payload = _mapping(raw.get("payload"))
    row_number = _number(payload.get("row"))
    row = int(row_number) if row_number is not None else None

    definitions = {
        "row_gain": ("set_row_gain", "row", ("new_gain", "after", "value")),
        "row_pan": ("set_row_pan", "row", ("new_pan", "after", "value")),
        "master_gain": ("set_master_gain", None, ("new_gain", "after", "value")),
        "master_pan": ("set_master_pan", None, ("new_pan", "after", "value")),
    }
    if kind in definitions:
        action_type, row_key, value_keys = definitions[kind]
        value = _first_number(payload.get(key) for key in value_keys)
        if value is None or (row_key and row is None):
            return None
        data: dict[str, Any] = {"mode": "set", "value": value}
        if row_key:
            data["row"] = row
        return {"type": action_type, "data": data}

    master = kind == "master_fx_param"
    if kind in {"row_fx_param", "master_fx_param"}:
        index_value = _number(payload.get("index"))
        value = _first_number(
            payload.get(key) for key in ("new_value", "after", "value")
        )
        parameter = str(payload.get("param_id") or payload.get("param_name") or "").strip()
        if index_value is None or value is None or not parameter or (not master and row is None):
            return None
        effect = _effect_name(
            project,
            row=row,
            index=int(index_value),
            master=master,
        )
        if not effect:
            return None
        data = {
            "effect_name_contains": effect,
            "param_name": parameter,
            "mode": "set",
            "value": value,
        }
        if not master:
            data["row"] = row
        return {
            "type": "adjust_master_effect_param_by_name"
            if master
            else "adjust_effect_param_by_name",
            "data": data,
        }

    if kind in {"row_fx_insert", "master_fx_insert"}:
        effect = str(payload.get("effect") or payload.get("name") or "").strip()
        master = kind.startswith("master")
        if not effect or (not master and row is None):
            return None
        data = {"effect_name_contains": effect}
        if not master:
            data["row"] = row
        return {
            "type": "ensure_master_effect" if master else "ensure_effect",
            "data": data,
        }
    return None


def _candidate_actions(
    episode: dict[str, Any], project: dict[str, Any]
) -> list[tuple[dict[str, Any], str]]:
    result: list[tuple[dict[str, Any], str]] = []
    for raw_value in episode.get("actions_raw") or []:
        if not isinstance(raw_value, dict):
            continue
        data = raw_value.get("data")
        if raw_value.get("type") and isinstance(data, dict):
            result.append(
                (
                    {"type": str(raw_value["type"]), "data": dict(data)},
                    "ai",
                )
            )
            continue
        mapped = _manual_action(raw_value, project)
        if mapped is not None:
            result.append((mapped, "manual"))
    return result


def _outcome(episode: dict[str, Any]) -> tuple[int | None, float, str]:
    # Taxonomy annotations and playback are not quality judgments.
    outcome = episode.get("producer_outcome")
    if outcome == "accepted":
        return 1, 1.0, "producer_accepted"
    if outcome == "rejected":
        return 0, 1.0, "producer_rejected"
    return None, 0.0, "unconfirmed"


def _action_delta(project: dict[str, Any], action: dict[str, Any]) -> float | None:
    action_type = str(action.get("type") or "")
    data = _mapping(action.get("data"))
    value = _number(data.get("value"))
    if value is None:
        return _first_number((data.get("delta"), data.get("delta_norm")))
    if str(data.get("mode") or "delta").lower() != "set":
        return value
    if action_type.startswith("set_row_") and bus_target(project, action) is not None:
        current = _final_scalar(project, action)
        return value - current if current is not None else None
    if action_type.startswith("set_row_"):
        row_number = _number(data.get("row"))
        if row_number is None:
            return None
        rows = project.get("rows") or []
        row = next(
            (r for r in rows if isinstance(r, dict) and int(r.get("row", -1)) == int(row_number)),
            None,
        )
        mix = _mapping(row.get("mix")) if isinstance(row, dict) else {}
        current = _number(mix.get("gain_0to3" if action_type == "set_row_gain" else "pan_0to1"))
        return value - current if current is not None else None
    if action_type == "set_master_gain":
        return value - (_number(project.get("master_gain_0to3")) if _number(project.get("master_gain_0to3")) is not None else 1.0)
    if action_type == "set_master_pan":
        return value - (_number(project.get("master_pan_0to1")) if _number(project.get("master_pan_0to1")) is not None else 0.5)
    return None


def _same_target(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left.get("type") != right.get("type"):
        return False
    left_data = _mapping(left.get("data"))
    right_data = _mapping(right.get("data"))
    keys = ("row", "effect_name_contains", "param_name", "param_name_contains_any", "force_individual_row")
    return all(left_data.get(key) == right_data.get(key) for key in keys)


def _audio_delta(episode: dict[str, Any]) -> dict[str, float] | None:
    target = _mapping(episode.get("audio_target"))
    raw = _mapping(episode.get("audio_feature_delta"))
    if target.get("status") != "rendered" or not raw:
        return None
    return {
        key: number
        for key, value in raw.items()
        if (number := _number(value)) is not None
    }


def _split(group_id: str) -> str:
    bucket = int(group_id[:8], 16) % 100
    return "train" if bucket < 90 else "validation" if bucket < 95 else "test"


def _final_scalar(project: dict[str, Any], action: dict[str, Any]) -> float | None:
    kind, data = action["type"], _mapping(action.get("data"))
    if kind in {"set_master_gain", "set_master_pan"}:
        return _number(project.get("master_gain_0to3" if kind.endswith("gain") else "master_pan_0to1"))
    if kind in {"set_row_gain", "set_row_pan"}:
        bus = bus_target(project, action)
        if bus is not None:
            return _number(bus.get("gain" if kind.endswith("gain") else "pan"))
        row = next((row for row in project.get("rows", [])
                    if isinstance(row, dict) and row.get("row") == data.get("row")), {})
        return _number(_mapping(row.get("mix")).get("gain_0to3" if kind.endswith("gain") else "pan_0to1"))
    return None


def _final_scale(project: dict[str, Any], after: dict[str, Any], action: dict[str, Any]) -> float | None:
    # Preserve direction and out-of-range ratios for apply/reject supervision.
    # Only the magnitude objective is restricted to the runtime's scalar range.
    final = _final_scalar(after, action)
    if final is None:
        return None
    proposal = _action_delta(project, action)
    target = {"type": action["type"], "data": {**action["data"], "mode": "set", "value": final}}
    delta = _action_delta(project, target)
    if proposal is None or delta is None or abs(proposal) < 1e-9:
        return None
    ratio = delta / proposal
    return ratio


def supervision_project(episode: dict, trace: dict, action: dict) -> dict:
    """Use execution-time metadata only for labels, never inference features.

    An ensure followed by a parameter adjustment needs the actual newly created
    instance's initial value, which the pre-inference snapshot cannot contain.
    """
    project = trace["project_state"]
    position = trace["actions"].index(action)
    recreated = parameter_recreated(trace["actions"], position)
    if action["type"] not in PARAM_ACTIONS or (parameter_target(project, action) is not None and not recreated):
        return project
    effects = chain(project, action)
    token = str(action["data"].get("effect_name_contains") or "").lower()
    if effects is None or (not recreated and any(token in str(e.get("name", "")).lower() for e in effects)):
        return project
    executions = [e for e in episode.get("parameter_executions", [])
                  if isinstance(e, dict) and _same_target(action, _mapping(e.get("action")))]
    if len(executions) != 1:
        return project
    expected = "ensure_master_effect" if "master" in action["type"] else "ensure_effect"
    insertions = [a for a in trace["actions"][:position] if a["type"] == expected and
                  all(a["data"].get(k) == action["data"].get(k)
                      for k in ("row", "force_individual_row", "effect_name_contains"))]
    if len(insertions) != 1:
        return project
    enriched = copy.deepcopy(project)
    target_chain = chain(enriched, action)
    target_chain[:] = [e for e in target_chain if token not in str(e.get("name", "")).lower()]
    target_chain.append(copy.deepcopy(executions[0]["effect"]))
    return enriched


def convert_bundle(
    bundle: dict[str, Any], *, resolver: MixResolveService | None = None
) -> list[dict[str, Any]]:
    if bundle.get("schema_version") != CAPTURE_SCHEMA:
        raise ConversionError("unsupported_schema")
    consent_version = str(bundle.get("consent_version") or "").strip()
    if not consent_version:
        raise ConversionError("missing_consent")
    session_id = str(bundle.get("session_id") or "").strip()
    if not session_id:
        raise ConversionError("missing_session_id")
    episodes = bundle.get("episodes")
    if not isinstance(episodes, list):
        raise ConversionError("missing_episodes")
    feature_builder = resolver or MixResolveService()
    # Old session-salted project refs cannot establish independence.
    stable_group = bundle.get("source_group_ref") or (
        bundle.get("project_ref") if bundle.get("segmentation_version") == "natural_action_burst_v2" else None
    )
    group_id = _sha256(str(stable_group or session_id))
    result: list[dict[str, Any]] = []
    for episode_index, episode in enumerate(episodes):
        if not isinstance(episode, dict):
            raise ConversionError("episode_not_object")
        project = _project(episode)
        after = _mapping(_mapping(episode.get("state_after")).get("project_state"))
        episode_label, episode_weight, episode_label_source = _outcome(episode)
        traces = episode.get("inference_traces") or []
        if not isinstance(traces, list):
            raise ConversionError("invalid_inference_traces")
        candidates: list[tuple[dict[str, Any], str, dict[str, Any] | None]] = []
        for trace in traces:
            if not isinstance(trace, dict) or trace.get("mix_feature_contract_version") != contract_version():
                raise ConversionError("inference_feature_contract_mismatch")
            if not isinstance(trace.get("project_state"), dict) or not isinstance(trace["project_state"].get("rows"), list):
                raise ConversionError("missing_inference_project")
            if not isinstance(trace.get("goal"), dict) or not isinstance(trace.get("strict"), bool):
                raise ConversionError("missing_inference_goal_or_strict")
            batch = trace.get("actions")
            if not isinstance(batch, list):
                raise ConversionError("missing_candidate_batch")
            for action in batch:
                if not isinstance(action, dict) or not isinstance(action.get("data"), dict) or not action.get("type"):
                    raise ConversionError("invalid_candidate_action")
                candidates.append((action, "ai", trace))
        raw_candidates = _candidate_actions(episode, after or project)
        candidates.extend((action, source, None) for action, source in raw_candidates if source == "manual" or not traces)
        for index, (action, source, trace) in enumerate(candidates):
            apply_label, weight, label_source = episode_label, episode_weight, episode_label_source
            reasons: list[str] = []
            features = None
            goal = None
            if trace is None:
                reasons.append("missing_exact_inference_context")
            else:
                goal = trace["goal"]
                features = feature_builder.build_training_feature_vector(
                    project=trace["project_state"], goal=goal, action=action,
                    strict=trace["strict"], candidate_actions=trace["actions"],
                )
                if trace.get("fallback_used") is True:
                    reasons.append("inference_fallback")
                # A candidate suppressed by the model was never auditioned.
                resolved = trace.get("resolved_actions") or []
                if not any(isinstance(item, dict) and _same_target(action, item) for item in resolved):
                    reasons.append("candidate_not_auditioned")
                if sum(_same_target(action, item) for t in traces for item in t["actions"]) != 1:
                    reasons.append("ambiguous_proposal_target")
            if not stable_group:
                reasons.append("missing_stable_source_group")
            if episode.get("status") != "complete":
                reasons.append("episode_not_complete")
            if "row" in action["data"] and trace is not None:
                target_row = action["data"]["row"]
                before_row = next((r for r in project.get("rows", []) if isinstance(r, dict) and r.get("row") == target_row), {})
                after_row = next((r for r in after.get("rows", []) if isinstance(r, dict) and r.get("row") == target_row), {})
                identity = _mapping(trace.get("row_identities")).get(str(target_row), before_row.get("row_id"))
                if not after_row:
                    reasons.append("target_track_removed")
                elif identity is None or after_row.get("row_id") is None:
                    reasons.append("missing_track_identity")
                elif identity != after_row["row_id"]:
                    reasons.append("target_track_changed")
            if action["type"] in {"set_row_gain", "set_row_pan", "set_master_gain", "set_master_pan"}:
                if _final_scalar(after, action) is None:
                    reasons.append("missing_final_target")
                if trace is not None and _final_scalar(trace["project_state"], action) is None:
                    reasons.append("missing_initial_target")
            if episode.get("capture_warning"):
                reasons.append("capture_warning")
            if not after or not isinstance(after.get("rows"), list):
                reasons.append("missing_final_state")
            signals = _mapping(episode.get("outcome_signals"))
            if signals.get("undo_redo_observed") or signals.get("rejected_by_undo"):
                reasons.append("ambiguous_history_change")
            if action["type"] not in SUPPORTED_MODEL_ACTIONS:
                reasons.append("unsupported_model_action")
            label_project = supervision_project(episode, trace, action) if trace else project
            plugin_target, plugin_reasons = plugin_supervision(label_project, after, action) if trace and after else (None, [])
            if plugin_target is not None and trace and label_project is not trace["project_state"]:
                plugin_target["initial_value_source"] = "verified_parameter_execution"
            reasons.extend(plugin_reasons)
            scale = _final_scale(trace["project_state"], after, action) if trace and after else None
            if plugin_target is not None:
                scale = plugin_target.get("magnitude_scale")
            # Confirmed final states provide per-action labels even when only
            # part of a batch helped. Never extend this inference to skipped or
            # still-experimenting sessions. Whole-batch rejection stays explicit.
            if episode.get("producer_outcome") in {"accepted", "partial"}:
                if plugin_target is not None and not plugin_reasons:
                    if plugin_target.get("kind") != "continuous_parameter" or "direction_ratio" in plugin_target:
                        apply_label = int(plugin_target["preserved"])
                    else:
                        apply_label = None
                elif scale is not None:
                    apply_label = int(scale > 0.05)
                else:
                    apply_label = None
                weight = 1.0 if apply_label is not None else 0.0
                label_source = "producer_final_per_action"
            if apply_label is None:
                reasons.append("outcome_not_confirmed")
            eligible = not reasons
            magnitude = scale if eligible and apply_label == 1 and scale is not None and 0 <= scale <= 3 else None
            if magnitude is None:
                magnitude_reasons = [*reasons, "no_confirmed_scalar_target"]
            else:
                magnitude_reasons = []
            example_id = _sha256(f"{session_id}:{episode_index}:{index}:{json.dumps(action, sort_keys=True)}")
            result.append({
                "dataset_schema_version": DATASET_SCHEMA,
                "mix_feature_contract_version": contract_version(),
                "example_id": example_id, "group_id": group_id, "split": _split(group_id),
                "source": {
                    "capture_schema_version": CAPTURE_SCHEMA, "consent_version": consent_version,
                    "session_id": session_id, "episode_id": episode.get("episode_id", str(episode_index)),
                    "action_source": source, "label_source": label_source,
                    "inference_trace_index": next((i for i, t in enumerate(traces) if t is trace), None),
                    "model_context": trace.get("model_context", {}) if trace else {},
                },
                "candidate_action": action, "goal": goal, "feature_vector": features,
                "plugin_feature_contract_version": PLUGIN_CONTRACT,
                "plugin_feature_vector": extra_features(trace["project_state"], action) if trace else None,
                "final_plugin_target": plugin_target,
                "labels": {"apply": apply_label, "magnitude_scale": magnitude,
                    "acceptance": apply_label, "diagnoses": episode.get("diagnoses", []),
                    "strategies": episode.get("strategies", []), "audio_feature_delta": _audio_delta(episode)},
                "producer_notes": episode.get("producer_notes", ""),
                "sample_weight": weight,
                "eligibility": {"mix_apply": eligible, "mix_magnitude": magnitude is not None,
                    "diagnosis_strategy": _mapping(episode.get("provenance")).get("label") == "producer",
                    "producer_acceptance": apply_label is not None,
                    "audio_result_delta": _audio_delta(episode) is not None},
                "exclusion_reasons": {"mix_apply": reasons, "mix_magnitude": magnitude_reasons},
            })
    return result


def _local_documents(inputs: list[str]) -> Iterator[tuple[str, bytes]]:
    for raw in inputs:
        path = Path(raw).expanduser()
        candidates = sorted(path.rglob("*.json")) if path.is_dir() else [path]
        for candidate in candidates:
            if candidate.is_file() and not candidate.name.endswith(".upload.json"):
                yield str(candidate), candidate.read_bytes()


def _s3_documents(uri: str) -> Iterator[tuple[str, bytes]]:
    try:
        import boto3
    except ModuleNotFoundError as exc:
        raise RuntimeError("boto3 is required for s3:// input") from exc
    parsed = urlparse(uri)
    bucket, prefix = parsed.netloc, parsed.path.lstrip("/")
    client = boto3.client("s3")
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents") or []:
            key = str(item.get("Key") or "")
            if key.endswith("/bundle.json") or key.endswith(".json"):
                body = client.get_object(Bucket=bucket, Key=key)["Body"].read()
                yield f"s3://{bucket}/{key}", body


def _documents(inputs: list[str]) -> Iterator[tuple[str, bytes]]:
    local = [item for item in inputs if not item.startswith("s3://")]
    yield from _local_documents(local)
    for item in inputs:
        if item.startswith("s3://"):
            yield from _s3_documents(item)


def _upload_directory(directory: Path, output_uri: str) -> None:
    import boto3

    parsed = urlparse(output_uri)
    bucket, prefix = parsed.netloc, parsed.path.strip("/")
    client = boto3.client("s3")
    for path in sorted(directory.iterdir()):
        key = "/".join(part for part in (prefix, path.name) if part)
        client.upload_file(
            str(path),
            bucket,
            key,
            ExtraArgs={"ServerSideEncryption": "AES256"},
        )


def _mark_ingestion(
    table_name: str,
    source: str,
    *,
    status: str,
    output: str,
    example_count: int = 0,
    error: str = "",
) -> None:
    if not table_name or not source.startswith("s3://"):
        return
    match = re.search(r"/user=([^/]+)/session=([^/]+)/bundle\.json$", source)
    if match is None:
        return
    import boto3

    now = datetime.now(timezone.utc).isoformat()
    values: dict[str, Any] = {
        ":ingestion": status,
        ":updated_at": now,
        ":dataset": output,
        ":count": example_count,
    }
    expression = (
        "SET ingestion_status = :ingestion, updated_at = :updated_at, "
        "training_dataset_location = :dataset, converted_example_count = :count"
    )
    if error:
        expression += ", conversion_error = :error"
        values[":error"] = error[:500]
    table = boto3.resource("dynamodb").Table(table_name)
    table.update_item(
        Key={"user_hash": match.group(1), "session_id": match.group(2)},
        UpdateExpression=expression,
        ExpressionAttributeValues=values,
    )


def run(
    inputs: list[str],
    output: str,
    *,
    shard_size: int = 10_000,
    sessions_table: str = "",
) -> dict[str, Any]:
    is_s3_output = output.startswith("s3://")
    temp = tempfile.TemporaryDirectory() if is_s3_output else None
    output_dir = Path(temp.name) if temp else Path(output).expanduser()
    writer = JsonlShardWriter(output_dir, shard_size)
    archive_writer = JsonlShardWriter(output_dir, min(shard_size, 100), prefix="episodes")
    archived_ids: set[str] = set()
    stats = ConversionStats()
    seen_examples: set[str] = set()
    converted_sources: list[tuple[str, int]] = []
    resolver = MixResolveService()
    try:
        for source, body in _documents(inputs):
            stats.bundles_seen += 1
            try:
                decoded = json.loads(body)
                if not isinstance(decoded, dict):
                    raise ConversionError("bundle_not_object")
                episodes = decoded.get("episodes")
                stats.episodes_seen += len(episodes) if isinstance(episodes, list) else 0
                examples = convert_bundle(decoded, resolver=resolver)
                for example in examples:
                    if example["example_id"] in seen_examples:
                        continue
                    seen_examples.add(example["example_id"])
                    writer.write(example)
                    stats.examples_written += 1
                    stats.splits[example["split"]] += 1
                    stats.action_types[example["candidate_action"]["type"]] += 1
                    for objective, reasons in example["exclusion_reasons"].items():
                        for reason in reasons:
                            stats.exclusions[f"{objective}:{reason}"] += 1
                    for objective, eligible in example["eligibility"].items():
                        if eligible:
                            stats.objectives[objective] += 1
                for episode_index, episode in enumerate(decoded["episodes"]):
                    archive_id = _sha256(f"{decoded['session_id']}:{episode_index}")
                    if archive_id in archived_ids:
                        continue
                    archived_ids.add(archive_id)
                    archive_writer.write({
                        "schema_version": "producer_mixing_episode_archive_v1",
                        "archive_id": archive_id,
                        "session_id": decoded["session_id"],
                        "consent_version": decoded["consent_version"],
                        "project_ref": decoded.get("project_ref"),
                        "source_group_ref": decoded.get("source_group_ref"),
                        "segmentation_version": decoded.get("segmentation_version"),
                        "episode": episode,
                        "events": [event for event in decoded.get("event_journal", [])
                                   if isinstance(event, dict) and _mapping(event.get("payload")).get("episode_id") == episode.get("episode_id", str(episode_index))],
                        "session_context_events": [event for event in decoded.get("event_journal", [])
                                                   if isinstance(event, dict) and not _mapping(event.get("payload")).get("episode_id")],
                    })
                stats.bundles_converted += 1
                converted_sources.append((source, len(examples)))
            except (ConversionError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
                reason = str(exc) or exc.__class__.__name__
                stats.errors[reason] += 1
                print(f"Skipping {source}: {reason}", file=sys.stderr)
                _mark_ingestion(
                    sessions_table,
                    source,
                    status="conversion_failed",
                    output=output,
                    error=reason,
                )
        writer.finish()
        archive_writer.finish()
        manifest = stats.manifest(shards=writer.shards)
        manifest["episode_archive_shards"] = archive_writer.shards
        manifest["episodes_archived"] = len(archived_ids)
        (output_dir / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if is_s3_output:
            _upload_directory(output_dir, output)
        for source, count in converted_sources:
            _mark_ingestion(sessions_table, source, status="converted", output=output, example_count=count)
        return manifest
    finally:
        writer.close_handle()
        archive_writer.close_handle()
        if temp is not None:
            temp.cleanup()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", help="JSON file, directory, or s3:// prefix")
    parser.add_argument("--output", required=True, help="Output directory or s3:// prefix")
    parser.add_argument("--shard-size", type=int, default=10_000)
    parser.add_argument(
        "--sessions-table",
        default="",
        help="Optional DynamoDB table to mark converted or failed ingestion status",
    )
    args = parser.parse_args(argv)
    manifest = run(
        args.inputs,
        args.output,
        shard_size=args.shard_size,
        sessions_table=args.sessions_table,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0 if not manifest["errors"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
