#!/usr/bin/env python3
"""Convert producer capture v4 bundles into sharded model-training JSONL."""

from __future__ import annotations

import argparse
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

CAPTURE_SCHEMA = "producer_training_capture_v4"
DATASET_SCHEMA = "producer_training_examples_v1"
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

    def manifest(self, *, shards: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "dataset_schema_version": DATASET_SCHEMA,
            "source_schema_version": CAPTURE_SCHEMA,
            "mix_feature_contract_version": contract_version(),
            "feature_count": 77,
            "bundles_seen": self.bundles_seen,
            "bundles_converted": self.bundles_converted,
            "episodes_seen": self.episodes_seen,
            "examples_written": self.examples_written,
            "errors": dict(sorted(self.errors.items())),
            "objective_example_counts": dict(sorted(self.objectives.items())),
            "split_counts": dict(sorted(self.splits.items())),
            "action_type_counts": dict(sorted(self.action_types.items())),
            "shards": shards,
        }


class JsonlShardWriter:
    def __init__(self, directory: Path, shard_size: int) -> None:
        self.directory = directory
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
        name = f"examples-{self._shard_count:05d}.jsonl"
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


def _project_after(episode: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    after = _mapping(episode.get("state_after"))
    project = _mapping(after.get("project_state"))
    return project if isinstance(project.get("rows"), list) else fallback


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


def _goal(episode: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    diagnosis = str(episode.get("diagnosis") or "other").strip().lower()
    kind = {
        "tone": "eq",
        "masking": "balance",
        "level_balance": "gain",
        "dynamics": "compressor",
        "space_depth": "reverb",
        "stereo_image": "pan",
        "distortion_noise": "distortion",
    }.get(diagnosis, "balance")
    action_type = str(action.get("type") or "")
    scope = "master" if "master" in action_type else "row" if "row" in action_type or "effect" in action_type else "auto"
    request = _mapping(episode.get("request_or_context"))
    return {
        "intensity": 0.5,
        "execution_profile": "producer_safe",
        "audibility": "noticeable",
        "target": {"scope": scope},
        "intents": [{"kind": kind}],
        "instruction_present": bool(str(request.get("prompt") or "").strip()),
    }


def _outcome(episode: dict[str, Any]) -> tuple[int, float, str]:
    signals = _mapping(episode.get("outcome_signals"))
    rejected = episode.get("status") == "rejected" or (
        signals.get("rejected_by_undo") is True
        and signals.get("restored_by_redo") is not True
    )
    if rejected:
        return 0, 1.0, "producer_rejected"
    provenance = _mapping(episode.get("provenance"))
    if provenance.get("label") == "producer":
        return 1, 1.0, "producer_confirmed"
    if signals.get("survived_next_playback") is True:
        return 1, 0.9, "implicit_playback_acceptance"
    confidence = _number(provenance.get("confidence")) or 0.0
    if provenance.get("label") == "inferred":
        return 1, max(0.35, min(0.65, confidence)), "inferred_acceptance"
    return 1, 0.25, "unconfirmed_completion"


def _action_delta(project: dict[str, Any], action: dict[str, Any]) -> float | None:
    action_type = str(action.get("type") or "")
    data = _mapping(action.get("data"))
    value = _number(data.get("value"))
    if value is None:
        return _first_number((data.get("delta"), data.get("delta_norm")))
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
        return value - (_number(project.get("master_gain_0to3")) or 1.0)
    if action_type == "set_master_pan":
        return value - (_number(project.get("master_pan_0to1")) or 0.5)
    return None


def _same_target(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left.get("type") != right.get("type"):
        return False
    left_data = _mapping(left.get("data"))
    right_data = _mapping(right.get("data"))
    keys = ("row", "effect_name_contains", "param_name")
    return all(left_data.get(key) == right_data.get(key) for key in keys)


def _magnitude_scale(
    project: dict[str, Any],
    actions: list[tuple[dict[str, Any], str]],
    index: int,
    apply_label: int,
) -> float | None:
    action, source = actions[index]
    if source != "ai":
        return None
    if apply_label == 0:
        return 0.0
    ai_delta = _action_delta(project, action)
    correction = next(
        (
            candidate
            for candidate, candidate_source in actions[index + 1 :]
            if candidate_source == "manual" and _same_target(action, candidate)
        ),
        None,
    )
    if correction is None:
        return 1.0
    final_delta = _action_delta(project, correction)
    if ai_delta is None or final_delta is None or abs(ai_delta) < 1e-9:
        return None
    scale = final_delta / ai_delta
    return max(0.0, min(3.0, scale))


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
    group_id = _sha256(session_id)
    result: list[dict[str, Any]] = []
    for episode_index, raw_episode in enumerate(episodes):
        if not isinstance(raw_episode, dict):
            continue
        project = _project(raw_episode)
        actions = _candidate_actions(raw_episode, _project_after(raw_episode, project))
        apply_label, sample_weight, label_source = _outcome(raw_episode)
        diagnoses = raw_episode.get("diagnoses")
        if not isinstance(diagnoses, list) or not diagnoses:
            diagnoses = [str(raw_episode.get("diagnosis") or "other")]
        strategies = raw_episode.get("strategies")
        if not isinstance(strategies, list):
            strategies = []
        audio_delta = _audio_delta(raw_episode)
        for action_index, (action, source) in enumerate(actions):
            goal = _goal(raw_episode, action)
            features = feature_builder.build_training_feature_vector(
                project=project,
                goal=goal,
                action=action,
                strict=False,
            )
            magnitude_scale = _magnitude_scale(
                project, actions, action_index, apply_label
            )
            supported = action["type"] in SUPPORTED_MODEL_ACTIONS
            example_id = _sha256(
                f"{session_id}:{episode_index}:{action_index}:{json.dumps(action, sort_keys=True)}"
            )
            eligibility = {
                "mix_apply": supported,
                "mix_magnitude": supported and magnitude_scale is not None,
                "diagnosis_strategy": True,
                "producer_acceptance": True,
                "audio_result_delta": audio_delta is not None,
            }
            result.append(
                {
                    "dataset_schema_version": DATASET_SCHEMA,
                    "mix_feature_contract_version": contract_version(),
                    "example_id": example_id,
                    "group_id": group_id,
                    "split": _split(group_id),
                    "source": {
                        "capture_schema_version": CAPTURE_SCHEMA,
                        "consent_version": consent_version,
                        "action_source": source,
                        "episode_disposition": str(raw_episode.get("disposition") or ""),
                        "label_source": label_source,
                    },
                    "candidate_action": action,
                    "goal": goal,
                    "feature_vector": features,
                    "labels": {
                        "apply": apply_label,
                        "magnitude_scale": magnitude_scale,
                        "acceptance": apply_label,
                        "diagnoses": sorted({str(item) for item in diagnoses}),
                        "strategies": sorted({str(item) for item in strategies}),
                        "audio_feature_delta": audio_delta,
                    },
                    "sample_weight": sample_weight,
                    "eligibility": eligibility,
                }
            )
    return result


def _local_documents(inputs: list[str]) -> Iterator[tuple[str, bytes]]:
    for raw in inputs:
        path = Path(raw).expanduser()
        candidates = sorted(path.rglob("*.json")) if path.is_dir() else [path]
        for candidate in candidates:
            if candidate.is_file():
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
    stats = ConversionStats()
    seen_examples: set[str] = set()
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
                    for objective, eligible in example["eligibility"].items():
                        if eligible:
                            stats.objectives[objective] += 1
                stats.bundles_converted += 1
                _mark_ingestion(
                    sessions_table,
                    source,
                    status="converted",
                    output=output,
                    example_count=len(examples),
                )
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
        manifest = stats.manifest(shards=writer.shards)
        (output_dir / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if is_s3_output:
            _upload_directory(output_dir, output)
        return manifest
    finally:
        writer.close_handle()
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
