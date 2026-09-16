#!/usr/bin/env python3
"""Audit closed producer sessions locally and optionally verify their real uploads.

With no path argument, prompts for a project folder. Remote verification is
read-only and uses the operator's existing AWS credentials.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
from pathlib import Path
from typing import Any

from producer_capture_converter import CAPTURE_SCHEMA, convert_bundle, run
from train_mix_refine_models import load_objective


class _ObservedRunner:
    def __init__(self, plugins=False) -> None:
        self.plugins = plugins
        self.features: list[list[float]] = []

    def feature_contract(self):
        return "mix_refine_plugins_v2" if self.plugins else "mix_refine_v1"

    def predict_apply_score(self, vector):
        self.features.append(vector)
        return 0.9

    def predict_scalar(self, vector):
        return 1.0

    def observability_context(self):
        return {}


def audit_document(document: dict[str, Any]) -> dict[str, Any]:
    if document.get("schema_version") != CAPTURE_SCHEMA:
        raise ValueError("Unsupported capture schema")
    if not document.get("ended_at"):
        raise ValueError("Session is still recording or did not close cleanly")
    episodes = document.get("episodes")
    if not isinstance(episodes, list) or not episodes:
        raise ValueError("Session contains no episodes")
    if any(e.get("status") == "active" for e in episodes):
        raise ValueError("Closed session contains an active episode")
    examples = convert_bundle(document)
    # Test real inference execution with a deterministic runner, not just length.
    from common.mix_resolve import MixResolveService
    expected = []
    expected_plugins = []
    for episode in episodes:
        for trace in episode.get("inference_traces") or []:
            runner = _ObservedRunner()
            result = MixResolveService(runner=runner).resolve(
                project=trace["project_state"], goal=trace["goal"],
                actions=trace["actions"], strict=trace["strict"],
            )
            if not result["fallback_used"]:
                expected.extend(runner.features)
            plugin_runner = _ObservedRunner(plugins=True)
            plugin_result = MixResolveService(runner=plugin_runner).resolve(
                project=trace["project_state"], goal=trace["goal"],
                actions=trace["actions"], strict=trace["strict"],
            )
            if not plugin_result["fallback_used"]:
                expected_plugins.extend(plugin_runner.features)
    # Exempt captured fallback requests, which are excluded from training.
    eligible = [row for row in examples if row["eligibility"]["mix_apply"]]
    for row in eligible:
        if row["feature_vector"] not in expected:
            raise ValueError("Eligible example differs from online feature extraction")
        if [*row["feature_vector"], *row["plugin_feature_vector"]] not in expected_plugins:
            raise ValueError("Eligible plugin example differs from online feature extraction")
    return {
        "session_id": document["session_id"],
        "episodes": len(episodes), "examples": len(examples),
        "eligible_apply": len(eligible),
        "eligible_magnitude": sum(row["eligibility"]["mix_magnitude"] for row in examples),
        "eligible_plugin_apply": sum(r["eligibility"]["mix_apply"] and r.get("final_plugin_target") is not None for r in examples),
        "eligible_plugin_magnitude": sum(r["eligibility"]["mix_magnitude"] and r.get("final_plugin_target") is not None for r in examples),
        "explicit_outcomes": sum(e.get("producer_outcome") in {"accepted", "rejected", "partial"} for e in episodes),
        "inference_traces": sum(len(e.get("inference_traces") or []) for e in episodes),
        "online_feature_parity": "passed" if eligible else "no_eligible_examples",
        "audio_pairs": len(document.get("media_manifest") or []),
        "upload_status": (document.get("upload") or {}).get("status", "wire_payload"),
    }


def verify_remote(files: list[Path], *, stack: str, region: str) -> dict[str, dict[str, str]]:
    import boto3
    session = boto3.Session(region_name=region)
    cloudformation = session.client("cloudformation")
    def resource(logical_id):
        return cloudformation.describe_stack_resource(StackName=stack, LogicalResourceId=logical_id)["StackResourceDetail"]["PhysicalResourceId"]
    bucket = resource("ProducerTrainingBucket")
    table = session.resource("dynamodb").Table(resource("ProducerTrainingSessionsTable"))
    s3 = session.client("s3")
    keys = {}
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="structured/"):
        for item in page.get("Contents", []):
            match = re.fullmatch(r"structured/user=([^/]+)/session=([^/]+)/bundle.json", item["Key"])
            if match:
                keys.setdefault(match[2], []).append((match[1], item["Key"]))
    reports = {}
    for file in files:
        document = json.loads(file.read_text())
        identifier = document["session_id"]
        matches = keys.get(identifier, [])
        if len(matches) != 1:
            raise ValueError(f"{identifier}: expected exactly one verified storage object, found {len(matches)}")
        user_hash, key = matches[0]
        item = table.get_item(Key={"user_hash": user_hash, "session_id": identifier}, ConsistentRead=True).get("Item", {})
        if item.get("status") != "verified" or item.get("ingestion_status") not in {"ready_for_conversion", "converted"}:
            raise ValueError(f"{identifier}: backend has not verified ingestion")
        response = s3.get_object(Bucket=bucket, Key=key)
        raw = response["Body"].read()
        digest = hashlib.sha256(raw).hexdigest()
        if digest != item.get("sha256") or len(raw) != int(item.get("size_bytes", -1)) or digest != response.get("Metadata", {}).get("sha256"):
            raise ValueError(f"{identifier}: backend checksum/size mismatch")
        payload = Path(str(file) + ".payload")
        if not payload.exists():
            raise ValueError(f"{identifier}: frozen local .payload missing; use a newly uploaded session")
        if raw != payload.read_bytes():
            raise ValueError(f"{identifier}: uploaded bytes differ from frozen local payload")
        wire = json.loads(raw)
        local_examples = convert_bundle(document)
        remote_examples = convert_bundle(wire)
        if local_examples != remote_examples:
            raise ValueError(f"{identifier}: upload sanitization changed training semantics")
        audit_document(wire)
        reports[identifier] = {"storage_verified": "passed", "exact_uploaded_bytes": "passed", "conversion_parity": "passed"}
    return reports


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", help="Project folder, producer_sessions folder, or one closed JSON session")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-upload", action="store_true")
    parser.add_argument("--require-plugin-eligible", action="store_true", help="Require eligible plugin apply and continuous parameter targets")
    parser.add_argument("--require-eligible", action="store_true", help="Require at least one eligible apply and magnitude example")
    parser.add_argument("--stack", default="mixroom-app-api-prod")
    parser.add_argument("--region", default="ap-northeast-2")
    args = parser.parse_args()
    path = Path((args.path or input("Paste the full project folder or capture JSON path: ")).strip().strip("\"'")).expanduser()
    if (path / "exports" / "producer_sessions").is_dir():
        path = path / "exports" / "producer_sessions"
    files = sorted(path.glob("*.json")) if path.is_dir() else [path]
    files = [file for file in files if json.loads(file.read_text()).get("schema_version") == CAPTURE_SCHEMA]
    if not files:
        raise ValueError("No v4 capture sessions found")
    output = args.output or Path(tempfile.mkdtemp(prefix="mixroom-capture-audit-"))
    output.mkdir(parents=True, exist_ok=True)
    reports, errors = [], []
    for file in files:
        try:
            reports.append(audit_document(json.loads(file.read_text())))
        except (ValueError, KeyError, TypeError) as exc:
            errors.append({"file": file.name, "error": str(exc)})
    manifest = run([str(file) for file in files], str(output / "dataset"))
    try:
        apply = load_objective(output / "dataset", "mix_apply", plugins=True)
        magnitude = load_objective(output / "dataset", "mix_magnitude", plugins=True)
        if args.require_eligible and (not apply.labels or not magnitude.labels):
            errors.append({"error": "No eligible apply and/or magnitude examples. Inspect exclusion_reason_counts."})
    except ValueError as exc:
        errors.append({"error": str(exc)})
    if args.require_plugin_eligible and (not sum(r["eligible_plugin_apply"] for r in reports) or not sum(r["eligible_plugin_magnitude"] for r in reports)):
        errors.append({"error": "No eligible plugin apply and/or plugin magnitude examples. Capture an auditioned plugin correction."})
    remote = {}
    if args.verify_upload:
        try:
            remote = verify_remote(files, stack=args.stack, region=args.region)
        except Exception as exc:
            errors.append({"error": f"Remote verification failed: {exc}"})
    report = {"format_validation": "failed" if errors else "passed", "sessions": reports,
              "remote": remote, "errors": errors, "conversion_manifest": manifest,
              "dataset_directory": str(output / "dataset"),
              "quality_improvement_proven": False}
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Report: {output / 'verification.json'}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
