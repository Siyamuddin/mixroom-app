#!/usr/bin/env python3
"""Train and export mix_refine_v1 apply and magnitude ONNX models."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

FEATURE_COUNT = 77
FEATURE_CONTRACT = "mix_refine_v1"


@dataclass(frozen=True)
class ObjectiveRows:
    features: list[list[float]]
    labels: list[float]
    weights: list[float]
    splits: list[str]


def _examples(dataset_dir: Path) -> Iterator[dict[str, Any]]:
    manifest = json.loads((dataset_dir / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("mix_feature_contract_version") != FEATURE_CONTRACT:
        raise ValueError("Dataset feature contract does not match mix_refine_v1.")
    for shard in manifest.get("shards") or []:
        path = dataset_dir / str(shard["name"])
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def load_objective(dataset_dir: Path, objective: str) -> ObjectiveRows:
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
            or not isinstance(label, (int, float))
        ):
            raise ValueError(f"Invalid {objective} training example.")
        features.append([float(value) for value in vector])
        labels.append(float(label))
        weights.append(float(example.get("sample_weight") or 1.0))
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
    if len(apply.labels) < minimum_apply:
        raise ValueError(f"Need at least {minimum_apply} eligible apply examples.")
    if len(set(apply.labels)) < 2:
        raise ValueError("Apply training requires both accepted and rejected examples.")
    if len(magnitude.labels) < minimum_magnitude:
        raise ValueError(
            f"Need at least {minimum_magnitude} eligible AI magnitude examples."
        )
    if not any(split == "train" for split in apply.splits + magnitude.splits):
        raise ValueError("Dataset has no training split.")


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
) -> dict[str, Any]:
    try:
        import numpy as np
        from sklearn.linear_model import LogisticRegression, Ridge
        from sklearn.metrics import accuracy_score, mean_absolute_error, roc_auc_score
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "Install backend/training/requirements.txt before training."
        ) from exc

    apply = load_objective(dataset_dir, "mix_apply")
    magnitude = load_objective(dataset_dir, "mix_magnitude")
    validate_readiness(
        apply,
        magnitude,
        minimum_apply=minimum_apply,
        minimum_magnitude=minimum_magnitude,
    )
    apply_x, apply_y, apply_w = _arrays(apply, "train", np)
    magnitude_x, magnitude_y, magnitude_w = _arrays(magnitude, "train", np)
    apply_model = LogisticRegression(
        max_iter=1000,
        class_weight="balanced",
        random_state=42,
    ).fit(apply_x, apply_y.astype(np.int64), sample_weight=apply_w)
    magnitude_model = Ridge(alpha=1.0).fit(
        magnitude_x,
        magnitude_y,
        sample_weight=magnitude_w,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    input_type = [("features", FloatTensorType([None, FEATURE_COUNT]))]
    apply_path = output_dir / "mix_apply_classifier_producer_capture.onnx"
    magnitude_path = output_dir / "mix_magnitude_regressor_producer_capture.onnx"
    apply_path.write_bytes(
        convert_sklearn(apply_model, initial_types=input_type, target_opset=17).SerializeToString()
    )
    magnitude_path.write_bytes(
        convert_sklearn(
            magnitude_model, initial_types=input_type, target_opset=17
        ).SerializeToString()
    )

    metrics: dict[str, Any] = {
        "feature_contract": FEATURE_CONTRACT,
        "apply_examples": len(apply.labels),
        "magnitude_examples": len(magnitude.labels),
        "models": {
            "apply": apply_path.name,
            "magnitude": magnitude_path.name,
        },
    }
    apply_vx, apply_vy, _ = _arrays(apply, "validation", np)
    if len(apply_vy):
        probabilities = apply_model.predict_proba(apply_vx)[:, 1]
        metrics["apply_validation_accuracy"] = float(
            accuracy_score(apply_vy, probabilities >= 0.5)
        )
        if len(set(apply_vy.tolist())) > 1:
            metrics["apply_validation_auc"] = float(
                roc_auc_score(apply_vy, probabilities)
            )
    magnitude_vx, magnitude_vy, _ = _arrays(magnitude, "validation", np)
    if len(magnitude_vy):
        prediction = magnitude_model.predict(magnitude_vx)
        metrics["magnitude_validation_mae"] = float(
            mean_absolute_error(magnitude_vy, prediction)
        )
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
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    dataset = Path(args.dataset)
    apply = load_objective(dataset, "mix_apply")
    magnitude = load_objective(dataset, "mix_magnitude")
    if args.validate_only:
        print(
            json.dumps(
                {
                    "feature_contract": FEATURE_CONTRACT,
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
    )
    print(json.dumps(metrics, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
