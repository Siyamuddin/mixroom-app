#!/usr/bin/env python3
"""Train plugin-aware apply and continuous-parameter ONNX refinement models."""

from __future__ import annotations

import argparse
import json
import hashlib
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

FEATURE_COUNT = 77
FEATURE_CONTRACT = "mix_refine_v1"
PLUGIN_CONTRACT = "mix_refine_plugins_v2"
PLUGIN_FEATURE_COUNT = 141


@dataclass(frozen=True)
class ObjectiveRows:
    features: list[list[float]]
    labels: list[float]
    weights: list[float]
    splits: list[str]


def _examples(dataset_dir: Path) -> Iterator[dict[str, Any]]:
    manifest = json.loads((dataset_dir / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("mix_feature_contract_version") != FEATURE_CONTRACT or manifest.get("feature_count") != FEATURE_COUNT:
        raise ValueError("Dataset feature contract does not match mix_refine_v1.")
    if manifest.get("dataset_schema_version") != "producer_training_examples_v2":
        raise ValueError("Reconvert captures with the v2 converter before training.")
    if manifest.get("errors"):
        raise ValueError("Conversion errors must be resolved before training.")
    archive_ids = set()
    for shard in manifest.get("episode_archive_shards", []):
        name = str(shard["name"])
        if Path(name).name != name:
            raise ValueError("Invalid archive shard filename")
        raw = (dataset_dir / name).read_bytes()
        if len(raw) != shard.get("bytes") or hashlib.sha256(raw).hexdigest() != shard.get("sha256"):
            raise ValueError("Episode archive checksum or byte count mismatch")
        rows = [json.loads(line) for line in raw.decode().splitlines() if line.strip()]
        if len(rows) != shard.get("examples"):
            raise ValueError("Episode archive count mismatch")
        for row in rows:
            if row.get("schema_version") != "producer_mixing_episode_archive_v1" or not row.get("archive_id") or row["archive_id"] in archive_ids:
                raise ValueError("Invalid or duplicate episode archive")
            archive_ids.add(row["archive_id"])
    if manifest.get("episodes_archived", 0) != len(archive_ids):
        raise ValueError("Episode archive total mismatch")
    groups: dict[str, str] = {}
    seen: set[str] = set()
    count = 0
    for shard in manifest.get("shards") or []:
        name = str(shard["name"])
        if Path(name).name != name:
            raise ValueError("Invalid shard filename.")
        raw = (dataset_dir / name).read_bytes()
        if len(raw) != shard.get("bytes") or hashlib.sha256(raw).hexdigest() != shard.get("sha256"):
            raise ValueError("Shard checksum or byte count mismatch.")
        lines = [line for line in raw.decode("utf-8").splitlines() if line.strip()]
        if len(lines) != shard.get("examples"):
            raise ValueError("Shard example count mismatch.")
        for line in lines:
            example = json.loads(line)
            if example.get("mix_feature_contract_version") != FEATURE_CONTRACT or example.get("dataset_schema_version") != "producer_training_examples_v2":
                raise ValueError("Example contract mismatch.")
            identifier = example.get("example_id")
            group, split = example.get("group_id"), example.get("split")
            if not identifier or identifier in seen or not group or split not in {"train", "validation", "test"}:
                raise ValueError("Invalid identity, duplicate example, or split.")
            seen.add(identifier)
            if group in groups and groups[group] != split:
                raise ValueError("Source group leaks across dataset splits.")
            groups[group] = split
            vector = example.get("feature_vector")
            if vector is not None and (not isinstance(vector, list) or len(vector) != FEATURE_COUNT or
                any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in vector)):
                raise ValueError("Invalid feature vector.")
            count += 1
            yield example
    if count != manifest.get("examples_written"):
        raise ValueError("Dataset example count mismatch.")


def load_objective(dataset_dir: Path, objective: str, *, plugins: bool = False) -> ObjectiveRows:
    if objective not in {"mix_apply", "mix_magnitude"}:
        raise ValueError("Unknown objective.")
    features: list[list[float]] = []
    labels: list[float] = []
    weights: list[float] = []
    splits: list[str] = []
    label_key = "apply" if objective == "mix_apply" else "magnitude_scale"
    for example in _examples(dataset_dir):
        if _mapping(example.get("eligibility")).get(objective) is not True:
            continue
        vector = example.get("feature_vector")
        label = _mapping(example.get("labels")).get(label_key)
        if (
            not isinstance(vector, list)
            or len(vector) != FEATURE_COUNT
            or isinstance(label, bool)
            or not isinstance(label, (int, float))
            or not math.isfinite(label)
            or (objective == "mix_apply" and label not in (0, 1))
            or (objective == "mix_magnitude" and not 0 <= label <= 3)
        ):
            raise ValueError(f"Invalid {objective} training example.")
        if plugins:
            extension = example.get("plugin_feature_vector")
            if example.get("plugin_feature_contract_version") != PLUGIN_CONTRACT or not isinstance(extension, list) or len(extension) != 64 or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in extension):
                raise ValueError("Reconvert captures with the plugin feature contract before training.")
            vector = [*vector, *extension]
        features.append([float(value) for value in vector])
        labels.append(float(label))
        weight = example.get("sample_weight")
        if isinstance(weight, bool) or not isinstance(weight, (int, float)) or not math.isfinite(weight) or not 0 < weight <= 1:
            raise ValueError("Invalid eligible sample weight.")
        if _mapping(example.get("exclusion_reasons")).get(objective):
            raise ValueError("Eligible example has exclusion reasons.")
        weights.append(float(weight))
        splits.append(str(example.get("split") or "train"))
    return ObjectiveRows(features, labels, weights, splits)


def _mapping(value: Any) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def validate_readiness(
    apply: ObjectiveRows,
    magnitude: ObjectiveRows,
    *,
    minimum_apply: int,
    minimum_magnitude: int,
) -> None:
    for name, rows, minimum in (("apply", apply, minimum_apply), ("magnitude", magnitude, minimum_magnitude)):
        train_labels = [label for label, split in zip(rows.labels, rows.splits) if split == "train"]
        if len(train_labels) < minimum:
            raise ValueError(f"Need at least {minimum} eligible {name} training examples.")
        for split in ("train", "validation", "test"):
            values = [label for label, row_split in zip(rows.labels, rows.splits) if row_split == split]
            if not values:
                raise ValueError(f"Missing {name} {split} examples.")
            if name == "apply" and set(values) != {0.0, 1.0}:
                raise ValueError(f"Apply {split} requires both accepted and rejected examples.")


def validate_plugin_coverage(dataset_dir: Path) -> None:
    rows = [r for r in _examples(dataset_dir) if r.get("final_plugin_target")]
    for split in ("train", "validation", "test"):
        apply = {r["labels"]["apply"] for r in rows if r["split"] == split and r["eligibility"]["mix_apply"]}
        magnitude = [r for r in rows if r["split"] == split and r["eligibility"]["mix_magnitude"]]
        if apply != {0, 1} or not magnitude:
            raise ValueError(f"Plugin {split} needs accepted/rejected apply examples and continuous parameter corrections; level-only data cannot establish plugin readiness.")


def _arrays(rows: ObjectiveRows, split: str, np: Any) -> tuple[Any, Any, Any]:
    indices = [index for index, value in enumerate(rows.splits) if value == split]
    return (
        np.asarray([rows.features[index] for index in indices], dtype=np.float32),
        np.asarray([rows.labels[index] for index in indices], dtype=np.float32),
        np.asarray([rows.weights[index] for index in indices], dtype=np.float32),
    )


def train(
    dataset_dir: Path,
    output_dir: Path,
    *,
    minimum_apply: int = 100,
    minimum_magnitude: int = 100,
    feature_contract: str = PLUGIN_CONTRACT,
    magnitude_estimator: str = "gradient_boosting",
) -> dict[str, Any]:
    try:
        import numpy as np
        import onnx
        import onnxruntime as ort
        from sklearn.linear_model import LogisticRegression, Ridge
        from sklearn.ensemble import GradientBoostingRegressor
        from sklearn.pipeline import Pipeline
        from sklearn.preprocessing import StandardScaler
        from sklearn.metrics import accuracy_score, mean_absolute_error, roc_auc_score
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "Install backend/training/requirements.txt before training."
        ) from exc

    if feature_contract not in {FEATURE_CONTRACT, PLUGIN_CONTRACT}:
        raise ValueError("Unknown export feature contract")
    if magnitude_estimator not in {"gradient_boosting", "ridge"}:
        raise ValueError("Unknown magnitude estimator")
    plugins = feature_contract == PLUGIN_CONTRACT
    feature_count = PLUGIN_FEATURE_COUNT if plugins else FEATURE_COUNT
    apply = load_objective(dataset_dir, "mix_apply", plugins=plugins)
    magnitude = load_objective(dataset_dir, "mix_magnitude", plugins=plugins)
    validate_readiness(
        apply,
        magnitude,
        minimum_apply=minimum_apply,
        minimum_magnitude=minimum_magnitude,
    )
    if plugins:
        validate_plugin_coverage(dataset_dir)
    apply_x, apply_y, apply_w = _arrays(apply, "train", np)
    magnitude_x, magnitude_y, magnitude_w = _arrays(magnitude, "train", np)
    # Preserve the historical model family and preprocessing by default.
    apply_model = Pipeline([
        ("scaler", StandardScaler()),
        ("clf", LogisticRegression(max_iter=1000, class_weight="balanced",
                                   solver="liblinear", random_state=42)),
    ]).fit(apply_x, apply_y.astype(np.int64), clf__sample_weight=apply_w)
    estimator = (GradientBoostingRegressor(random_state=42)
                 if magnitude_estimator == "gradient_boosting" else Ridge(alpha=1.0))
    magnitude_model = Pipeline([
        ("scaler", StandardScaler()), ("reg", estimator),
    ]).fit(magnitude_x, magnitude_y, reg__sample_weight=magnitude_w)

    output_dir.mkdir(parents=True, exist_ok=False)
    input_type = [("features", FloatTensorType([None, feature_count]))]
    apply_path = output_dir / "mix_apply_classifier_producer_capture.onnx"
    magnitude_path = output_dir / "mix_magnitude_regressor_producer_capture.onnx"
    apply_path.write_bytes(
        convert_sklearn(apply_model, initial_types=input_type, target_opset=17, options={id(apply_model.named_steps["clf"]): {"zipmap": False}}).SerializeToString()
    )
    magnitude_path.write_bytes(
        convert_sklearn(
            magnitude_model, initial_types=input_type, target_opset=17
        ).SerializeToString()
    )

    for path in (apply_path, magnitude_path):
        model = onnx.load(str(path))
        onnx.helper.set_model_props(model, {"mix_feature_contract_version": feature_contract})
        onnx.save(model, str(path))

    eligible_examples = [e for e in _examples(dataset_dir) if e["eligibility"].get("mix_apply") or e["eligibility"].get("mix_magnitude")]
    from collections import Counter
    metrics: dict[str, Any] = {
        "feature_contract": feature_contract,
        "feature_count": feature_count,
        "magnitude_estimator": magnitude_estimator,
        "preprocessing": "standard_scaler",
        "runtime_targets": ["remote"] if plugins else ["remote", "local_dart"],
        "training_group_ids": sorted({e["group_id"] for e in eligible_examples if e["split"] == "train"}),
        "action_coverage": dict(Counter(e["candidate_action"]["type"] for e in eligible_examples)),
        "source_coverage": dict(Counter(e["source"].get("action_source", "legacy") for e in eligible_examples)),
        "validation_group_ids": sorted({e["group_id"] for e in eligible_examples if e["split"] == "validation"}),
        "test_group_ids": sorted({e["group_id"] for e in eligible_examples if e["split"] == "test"}),
        "plugin_parameter_coverage": dict(Counter(str((e.get("final_plugin_target") or {}).get("parameter_name")) for e in eligible_examples if e.get("final_plugin_target"))),
        "apply_examples": len(apply.labels),
        "magnitude_examples": len(magnitude.labels),
        "models": {
            "apply": apply_path.name,
            "magnitude": magnitude_path.name,
        },
    }
    for split in ("validation", "test"):
        ax, ay, _ = _arrays(apply, split, np)
        mx, my, _ = _arrays(magnitude, split, np)
        probabilities = apply_model.predict_proba(ax)[:, 1]
        metrics[f"apply_{split}_accuracy"] = float(accuracy_score(ay, probabilities >= 0.5))
        metrics[f"apply_{split}_auc"] = float(roc_auc_score(ay, probabilities))
        metrics[f"apply_{split}_always_accept_accuracy"] = float(np.mean(ay == 1))
        metrics[f"magnitude_{split}_mae"] = float(mean_absolute_error(my, magnitude_model.predict(mx)))
        metrics[f"magnitude_{split}_unchanged_mae"] = float(mean_absolute_error(my, np.ones_like(my)))
    # Verify the actual artifacts with the same output decoding as production.
    import sys
    proxy_src = Path(__file__).resolve().parents[1] / "llm_proxy" / "src"
    if str(proxy_src) not in sys.path:
        sys.path.insert(0, str(proxy_src))
    from common.mix_resolve import OnnxMixModelRunner
    decoder = OnnxMixModelRunner.__new__(OnnxMixModelRunner)
    decoder._np = np
    for path, model, rows, classifier in ((apply_path, apply_model, apply, True), (magnitude_path, magnitude_model, magnitude, False)):
        onnx.checker.check_model(str(path))
        session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
        x, _, _ = _arrays(rows, "test", np)
        if classifier:
            actual = [decoder._extract_apply_score(decoder._run_named_outputs(session, row.tolist())) for row in x]
            expected = model.predict_proba(x)[:, 1]
        else:
            actual = session.run(None, {session.get_inputs()[0].name: x})[0].reshape(-1)
            expected = model.predict(x)
        if not np.allclose(actual, expected, atol=1e-5, rtol=1e-5):
            raise ValueError("Exported ONNX predictions differ from trained model.")
    metrics["onnx_runtime_parity"] = "passed"
    metrics["publication_approved"] = False
    (output_dir / "training_manifest.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return metrics


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset")
    parser.add_argument("--output", required=True)
    parser.add_argument("--minimum-apply", type=int, default=100)
    parser.add_argument("--minimum-magnitude", type=int, default=100)
    parser.add_argument("--feature-contract", choices=(FEATURE_CONTRACT, PLUGIN_CONTRACT), default=PLUGIN_CONTRACT,
                        help="mix_refine_v1 exports the existing 77-feature remote/local model contract")
    parser.add_argument("--magnitude-estimator", choices=("gradient_boosting", "ridge"), default="gradient_boosting")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--require-ready", action="store_true", help="Also enforce sample and split readiness during validation")
    args = parser.parse_args()
    dataset = Path(args.dataset)
    plugins = args.feature_contract == PLUGIN_CONTRACT
    apply = load_objective(dataset, "mix_apply", plugins=plugins)
    magnitude = load_objective(dataset, "mix_magnitude", plugins=plugins)
    if args.validate_only:
        if args.require_ready:
            validate_readiness(apply, magnitude, minimum_apply=args.minimum_apply, minimum_magnitude=args.minimum_magnitude)
            if plugins:
                validate_plugin_coverage(dataset)
        print(
            json.dumps(
                {
                    "format_validation": "passed",
                    "readiness_checked": args.require_ready,
                    "feature_contract": args.feature_contract,
                    "feature_count": PLUGIN_FEATURE_COUNT if plugins else FEATURE_COUNT,
                    "apply_examples": len(apply.labels),
                    "magnitude_examples": len(magnitude.labels),
                    "apply_classes": sorted(set(apply.labels)),
                },
                indent=2,
            )
        )
        return 0
    metrics = train(
        dataset,
        Path(args.output),
        minimum_apply=args.minimum_apply,
        minimum_magnitude=args.minimum_magnitude,
        feature_contract=args.feature_contract,
        magnitude_estimator=args.magnitude_estimator,
    )
    print(json.dumps(metrics, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
