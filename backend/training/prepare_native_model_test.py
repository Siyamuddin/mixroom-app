#!/usr/bin/env python3
"""Package trained 77-feature models for the native Flutter integration test."""
import argparse
import base64
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.models / "training_manifest.json").read_text())
    if manifest.get("feature_contract") != "mix_refine_v1" or manifest.get("feature_count") != 77 or manifest.get("onnx_runtime_parity") != "passed":
        raise ValueError("Native test requires verified 77-feature exports")
    defines = {}
    for kind in ("apply", "magnitude"):
        name = manifest["models"][kind]
        if Path(name).name != name:
            raise ValueError("Invalid model filename")
        defines[f"PRO20_TEST_{kind.upper()}_MODEL"] = base64.b64encode((args.models / name).read_bytes()).decode()
    args.output.write_text(json.dumps(defines) + "\n")


if __name__ == "__main__":
    main()
