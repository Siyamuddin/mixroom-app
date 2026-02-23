#!/usr/bin/env python3
import ast
import pathlib
import re
import sys
from typing import Optional


def _extract_python_feature_columns(path: pathlib.Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    m = re.search(
        r"FEATURE_COLUMNS\s*=\s*\[(.*?)\]\s*EXPECTED_FEATURE_COUNT",
        text,
        flags=re.S,
    )
    if not m:
        raise RuntimeError(f"Could not parse FEATURE_COLUMNS in {path}")
    cols = ast.literal_eval("[" + m.group(1) + "]")
    if not isinstance(cols, list) or not all(isinstance(c, str) for c in cols):
        raise RuntimeError(f"FEATURE_COLUMNS in {path} is malformed")
    return cols


def _extract_python_expected_count(path: pathlib.Path) -> Optional[int]:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"EXPECTED_FEATURE_COUNT\s*=\s*(\d+)", text)
    if not m:
        return None
    return int(m.group(1))


def _extract_dart_feature_columns(path: pathlib.Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"kFeatureColumns\s*=\s*<String>\[(.*?)\]\s*;", text, flags=re.S)
    if not m:
        raise RuntimeError(f"Could not parse kFeatureColumns in {path}")
    return re.findall(r"'([^']+)'", m.group(1))


def _diff(a: list[str], b: list[str]) -> str:
    if a == b:
        return "ok"
    out = []
    max_len = max(len(a), len(b))
    for i in range(max_len):
        av = a[i] if i < len(a) else "<missing>"
        bv = b[i] if i < len(b) else "<missing>"
        if av != bv:
            out.append(f"  idx {i}: app='{av}' vs train='{bv}'")
    return "\n".join(out)


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    dart_file = repo_root / "lib/ai/onnx_magnitude_predictor.dart"
    py_files = [
        repo_root / "tools/ai_mixing/prepare_dataset.py",
        repo_root / "tools/ai_mixing/train.py",
        repo_root / "tools/ai_mixing/evaluate.py",
    ]

    dart_cols = _extract_dart_feature_columns(dart_file)

    first_py_cols = None
    ok = True

    for pf in py_files:
        py_cols = _extract_python_feature_columns(pf)
        expected_count = _extract_python_expected_count(pf)

        if expected_count is not None and expected_count != len(py_cols):
            ok = False
            print(
                f"[FAIL] {pf}: EXPECTED_FEATURE_COUNT={expected_count}, parsed={len(py_cols)}"
            )

        if first_py_cols is None:
            first_py_cols = py_cols
        elif py_cols != first_py_cols:
            ok = False
            print(f"[FAIL] Python FEATURE_COLUMNS mismatch in {pf}:")
            print(_diff(py_cols, first_py_cols))

    assert first_py_cols is not None
    if dart_cols != first_py_cols:
        ok = False
        print(f"[FAIL] Dart/Python feature order mismatch:")
        print(_diff(dart_cols, first_py_cols))

    if len(dart_cols) != len(first_py_cols):
        ok = False
        print(
            f"[FAIL] Feature count mismatch: app={len(dart_cols)} train={len(first_py_cols)}"
        )

    if not ok:
        return 1

    print(
        f"[OK] Feature contract verified ({len(dart_cols)} features): "
        f"{dart_file.name} == prepare_dataset.py == train.py == evaluate.py"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
