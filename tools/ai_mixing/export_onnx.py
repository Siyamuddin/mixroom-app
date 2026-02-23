#!/usr/bin/env python3
import argparse
import json
import os

import joblib
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType


def parse_args():
    p = argparse.ArgumentParser(description="Export trained sklearn models to ONNX.")
    p.add_argument("--model-dir", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--opset", type=int, default=17)
    return p.parse_args()


def main():
    args = parse_args()

    os.makedirs(args.out_dir, exist_ok=True)

    apply_model = joblib.load(os.path.join(args.model_dir, "apply_classifier.joblib"))
    reg_model = joblib.load(os.path.join(args.model_dir, "magnitude_regressor.joblib"))

    manifest_path = os.path.join(args.model_dir, "feature_manifest.json")
    if not os.path.exists(manifest_path):
        raise SystemExit("Missing feature_manifest.json in model-dir.")
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    feature_cols = manifest.get("feature_columns")
    if not isinstance(feature_cols, list) or not feature_cols:
        raise SystemExit("feature_manifest.json does not contain feature_columns.")

    initial_types = [("input", FloatTensorType([None, len(feature_cols)]))]

    # Force dense probability tensor output for classifier to keep runtime parsing simple.
    # Fallback to default conversion if backend does not support this option for a model.
    apply_options = {id(apply_model): {"zipmap": False}}
    try:
        apply_onnx = convert_sklearn(
            apply_model,
            initial_types=initial_types,
            target_opset=args.opset,
            options=apply_options,
        )
    except Exception:
        apply_onnx = convert_sklearn(
            apply_model, initial_types=initial_types, target_opset=args.opset
        )

    reg_onnx = convert_sklearn(reg_model, initial_types=initial_types, target_opset=args.opset)

    apply_out = os.path.join(args.out_dir, "mix_apply_classifier.onnx")
    reg_out = os.path.join(args.out_dir, "mix_magnitude_regressor.onnx")

    with open(apply_out, "wb") as f:
        f.write(apply_onnx.SerializeToString())

    with open(reg_out, "wb") as f:
        f.write(reg_onnx.SerializeToString())

    print(f"Wrote {apply_out}")
    print(f"Wrote {reg_out}")


if __name__ == "__main__":
    main()
