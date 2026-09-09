#!/usr/bin/env python3
"""Replay held-out captures through candidate and current production resolvers.

Measures producer-label agreement and effective correction scale, including
runtime floors/suppression. Does not render audio or establish listening quality.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import time
import statistics
from pathlib import Path

from producer_capture_converter import CAPTURE_SCHEMA, convert_bundle
from common.mix_resolve import MixResolveService, OnnxMixModelRunner, _ResolvedModelBundle
from common.mix_plugin_contract import PARAM_ACTIONS, parameter_target, proposed_value
from producer_capture_converter import _action_delta, supervision_project


class CandidateRunner(OnnxMixModelRunner):
    def __init__(self, directory: Path):
        super().__init__()
        self.directory = directory

    def _resolve_bundle(self):
        manifest = json.loads((self.directory / "training_manifest.json").read_text())
        self.training_groups = set(manifest.get("training_group_ids", []))
        paths = {}
        for kind in ("apply", "magnitude"):
            name = manifest["models"][kind]
            if Path(name).name != name:
                raise ValueError("Invalid model filename")
            paths[kind] = self.directory / name
        return _ResolvedModelBundle(source="review_directory", bundle_version=self.directory.name,
                                    apply_path=paths["apply"], magnitude_path=paths["magnitude"],
                                    apply_version=paths["apply"].stem, magnitude_version=paths["magnitude"].stem)


def evaluate(bundles: list[dict], *, candidate, baseline, split="test") -> dict:
    services = {"candidate": MixResolveService(runner=candidate), "baseline": MixResolveService(runner=baseline)}
    values = defaultdict(list)
    groups = set()
    seen = set()
    timings = defaultdict(list)
    for bundle in bundles:
        examples = convert_bundle(bundle)
        episodes = bundle["episodes"]
        for episode_index, episode in enumerate(episodes):
            eligible = [r for r in examples if r["source"]["episode_id"] == episode.get("episode_id", str(episode_index))
                        and r["split"] == split and r["eligibility"]["mix_apply"]]
            if not eligible:
                continue
            responses_by_trace = {}
            for trace_index in sorted({r["source"]["inference_trace_index"] for r in eligible}):
                trace = episode["inference_traces"][trace_index]
                responses = {}
                for name, service in services.items():
                    started = time.perf_counter()
                    responses[name] = service.resolve(project=trace["project_state"], goal=trace["goal"],
                        actions=trace["actions"], strict=trace["strict"])
                    timings[name].append((time.perf_counter() - started) * 1000)
                if any(response["fallback_used"] for response in responses.values()):
                    raise ValueError("Model replay fell back; verify model paths and feature contracts")
                responses_by_trace[trace_index] = responses
            for row in eligible:
                trace_index = row["source"]["inference_trace_index"]
                trace = episode["inference_traces"][trace_index]
                responses = responses_by_trace[trace_index]
                if row["example_id"] in seen:
                    continue
                seen.add(row["example_id"])
                if row["group_id"] in getattr(candidate, "training_groups", set()):
                    raise ValueError("Evaluation source group was used to train the candidate")
                groups.add(row["group_id"])
                index = trace["actions"].index(row["candidate_action"])
                slices = ("all", row["candidate_action"]["type"])
                for name, response in responses.items():
                    entries = [e for e in response["debug_entries"] if e["action_index"] == index]
                    if len(entries) != 1:
                        raise ValueError("Replay did not report exactly one decision per candidate")
                    entry = entries[0]
                    for category in slices:
                        values[f"{category}/{name}/apply_accuracy"].append(float((not entry["dropped"]) == bool(row["labels"]["apply"])))
                        if row["eligibility"]["mix_magnitude"]:
                            if entry["dropped"]:
                                effective_scale = 0.0
                            elif row["candidate_action"]["type"] in PARAM_ACTIONS:
                                parameter = parameter_target(supervision_project(episode, trace, row["candidate_action"]), row["candidate_action"])[1]
                                start = parameter["value"]
                                original = proposed_value(parameter, row["candidate_action"]["data"])
                                actual = proposed_value(parameter, entry["after"]["data"])
                                effective_scale = (actual - start) / (original - start)
                            else:
                                effective_scale = _action_delta(trace["project_state"], entry["after"]) / _action_delta(trace["project_state"], row["candidate_action"])
                            values[f"{category}/{name}/effective_scale_mae"].append(abs(effective_scale - row["labels"]["magnitude_scale"]))
                for category in slices:
                    values[f"{category}/always_accept/apply_accuracy"].append(float(row["labels"]["apply"]))
                    if row["eligibility"]["mix_magnitude"]:
                        values[f"{category}/unchanged/effective_scale_mae"].append(abs(1 - row["labels"]["magnitude_scale"]))
    if not seen:
        raise ValueError(f"No eligible {split} examples; collect held-out source groups")
    return {
        "split": split, "examples": len(seen), "source_groups": len(groups),
        "models": {"candidate": candidate.observability_context(), "baseline": baseline.observability_context()},
        "metrics": {key: {"count": len(items), "mean": sum(items) / len(items)} for key, items in sorted(values.items())},
        "resolver_latency_ms": {name: {"first_call": times[0], "warm_calls": len(times) - 1,
            "warm_median": statistics.median(times[1:]) if len(times) > 1 else None,
            "warm_max": max(times[1:]) if len(times) > 1 else None} for name, times in timings.items()},
        "listening_quality_verified": False, "publication_approved": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", help="Held-out project/capture directory or capture JSON")
    parser.add_argument("--candidate-directory", required=True, type=Path)
    parser.add_argument("--baseline-directory", type=Path, help="Prior trainer output; otherwise load currently configured/packaged models")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--split", choices=("validation", "test"), default="test")
    args = parser.parse_args()
    path = Path((args.path or input("Paste the held-out project/capture path: ")).strip().strip("\"'")).expanduser()
    if (path / "exports" / "producer_sessions").is_dir():
        path = path / "exports" / "producer_sessions"
    files = sorted(path.rglob("*.json")) if path.is_dir() else [path]
    documents = [json.loads(file.read_text()) for file in files]
    bundles = [d for d in documents if isinstance(d, dict) and d.get("schema_version") == CAPTURE_SCHEMA]
    result = evaluate(bundles, candidate=CandidateRunner(args.candidate_directory),
                      baseline=CandidateRunner(args.baseline_directory) if args.baseline_directory else OnnxMixModelRunner(), split=args.split)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
