#!/usr/bin/env python3
"""Import historical 77-feature CSV rows, optionally alongside v4 examples.

Historical labels retain their provenance. Missing plugin context is not filled
with invented values: train the combined dataset with --feature-contract mix_refine_v1.
"""
from __future__ import annotations

import argparse
import ast
import csv
import json
import math
import shutil
from pathlib import Path

from producer_capture_converter import ConversionStats, JsonlShardWriter, _sha256, _split
from train_mix_refine_models import _examples


def feature_columns() -> list[str]:
    # Read the authoritative legacy column order without importing its training
    # dependencies or duplicating the 77-column contract.
    path = Path(__file__).resolve().parents[2] / "tools/ai_mixing/train.py"
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "FEATURE_COLUMNS" for t in node.targets):
            columns = ast.literal_eval(node.value)
            if len(columns) == 77:
                return columns
    raise ValueError("Legacy feature contract missing")


def legacy_examples(path: Path, groups: dict[str, str]):
    columns = feature_columns()
    seen = set()
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        required = {*columns, "label_apply", "label_magnitude_scale", "project_id", "session_id", "action_type"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("Legacy CSV is missing feature, label or source identity columns")
        for index, raw in enumerate(reader):
            source = raw["project_id"].strip()
            if not source or not raw["session_id"].strip():
                raise ValueError("Legacy rows require project and session identities")
            if groups and (source not in groups or not isinstance(groups[source], str) or not groups[source]):
                raise ValueError(f"Missing canonical source group for legacy project {source}")
            vector = [float(raw[c]) for c in columns]
            label, magnitude = float(raw["label_apply"]), float(raw["label_magnitude_scale"])
            if not all(math.isfinite(v) for v in [*vector, label, magnitude]) or label not in (0, 1) or not 0 <= magnitude <= 3:
                raise ValueError(f"Invalid legacy features or labels at CSV row {index + 2}")
            group = _sha256(groups.get(source, source))
            identifier = _sha256("legacy:" + json.dumps(raw, sort_keys=True))
            if identifier in seen:
                continue
            seen.add(identifier)
            yield {
                "dataset_schema_version": "producer_training_examples_v2",
                "mix_feature_contract_version": "mix_refine_v1",
                "example_id": identifier, "group_id": group, "split": _split(group),
                "feature_vector": vector,
                "source": {"capture_schema_version": "legacy_csv", "session_id": raw["session_id"],
                           "episode_id": raw.get("cycle_id", ""), "label_source": "historical_pipeline"},
                "candidate_action": {"type": raw["action_type"], "data": {}},
                "labels": {"apply": int(label), "magnitude_scale": magnitude if label == 1 else None},
                "sample_weight": 1.0,
                "eligibility": {"mix_apply": True, "mix_magnitude": label == 1},
                "exclusion_reasons": {"mix_apply": [], "mix_magnitude": [] if label == 1 else ["rejected_action"]},
            }


def run(csv_path: Path, output: Path, *, dataset: Path | None = None, groups: dict[str, str] | None = None):
    if dataset is not None and not groups:
        raise ValueError("Combining old/new captures requires --group-map to keep the same song in one split")
    if output.exists():
        raise ValueError("Choose a new output directory")
    # Validate both inputs before writing. The historical CSV is an explicit
    # operator-selected dataset, never an automatic migration of unowned files.
    legacy = list(legacy_examples(csv_path, groups or {}))
    if not legacy:
        raise ValueError("Legacy CSV contains no training rows")
    current = list(_examples(dataset)) if dataset else []
    stats = ConversionStats()
    writer = JsonlShardWriter(output, 10000)
    seen = set()
    for row in [*current, *legacy]:
        if row["example_id"] in seen:
            continue
        seen.add(row["example_id"])
        # Recompute splits from canonical groups for both sources.
        row["split"] = _split(row["group_id"])
        writer.write(row)
        stats.examples_written += 1
        stats.action_types[row["candidate_action"]["type"]] += 1
        stats.splits[row["split"]] += 1
        for objective, eligible in row["eligibility"].items():
            if eligible:
                stats.objectives[objective] += 1
    writer.finish()
    manifest = stats.manifest(shards=writer.shards)
    manifest.update(source_schema_version="historical_and_v4", compatible_training_contracts=["mix_refine_v1"],
                    historical_examples=len(legacy), original_v4_dataset=str(dataset) if dataset else None,
                    historical_labels_revalidated=False)
    if dataset:
        original = json.loads((dataset / "manifest.json").read_text())
        manifest["episode_archive_shards"] = original.get("episode_archive_shards", [])
        manifest["episodes_archived"] = original.get("episodes_archived", 0)
        for shard in manifest["episode_archive_shards"]:
            shutil.copyfile(dataset / shard["name"], output / shard["name"])
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dataset", type=Path, help="Optional verified v4 dataset")
    parser.add_argument("--group-map", type=Path, help="JSON mapping each old project_id to its v4 source_group_ref/project_ref")
    args = parser.parse_args()
    groups = json.loads(args.group_map.read_text()) if args.group_map else {}
    if not isinstance(groups, dict):
        raise ValueError("Group map must be an object")
    print(json.dumps(run(args.csv, args.output, dataset=args.dataset, groups=groups), indent=2))


if __name__ == "__main__":
    main()
