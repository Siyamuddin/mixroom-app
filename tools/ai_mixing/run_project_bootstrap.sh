#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$ROOT_DIR/tools/ai_mixing"

PROJECTS_ROOT=""
OUT_ROOT="$TOOLS_DIR/out_project_bootstrap"
SEED="42"
TEST_SIZE="0.2"
COPY_ASSETS="0"
SKIP_PIP="0"

usage() {
  cat <<'EOF'
Usage:
  tools/ai_mixing/run_project_bootstrap.sh --projects-root /path/to/projects [options]

Required:
  --projects-root PATH      Mixroom project folder, directory of projects, or .mixroom bundle root.

Options:
  --out-root PATH           Output root (default: tools/ai_mixing/out_project_bootstrap)
  --seed INT                Random seed for train/eval split (default: 42)
  --test-size FLOAT         Holdout ratio for train/eval split (default: 0.2)
  --copy-assets             Copy exported ONNX files into assets/models
  --skip-pip                Skip pip install step
  -h, --help                Show this help
EOF
}

die() {
  echo "[error] $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects-root)
      PROJECTS_ROOT="${2:-}"; shift 2 ;;
    --out-root)
      OUT_ROOT="${2:-}"; shift 2 ;;
    --seed)
      SEED="${2:-}"; shift 2 ;;
    --test-size)
      TEST_SIZE="${2:-}"; shift 2 ;;
    --copy-assets)
      COPY_ASSETS="1"; shift ;;
    --skip-pip)
      SKIP_PIP="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

[[ -n "$PROJECTS_ROOT" ]] || die "--projects-root is required"
[[ -e "$PROJECTS_ROOT" ]] || die "Projects root not found: $PROJECTS_ROOT"

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  die "Virtual env is not active. Run: source .venv/bin/activate"
fi

DATASET_CSV="$OUT_ROOT/dataset.csv"
MODELS_DIR="$OUT_ROOT/models"
ONNX_DIR="$OUT_ROOT/onnx"
mkdir -p "$OUT_ROOT" "$MODELS_DIR" "$ONNX_DIR"

cd "$ROOT_DIR"

if [[ "$SKIP_PIP" != "1" ]]; then
  echo "[1/5] Installing/updating python dependencies..."
  pip install -r "$TOOLS_DIR/requirements.txt"
else
  echo "[1/5] Skipping pip install (--skip-pip)"
fi

echo "[2/5] Building dataset from finished Mixroom projects..."
python3 "$TOOLS_DIR/build_project_bootstrap_dataset.py" \
  --projects-root "$PROJECTS_ROOT" \
  --out-csv "$DATASET_CSV"

echo "[3/5] Training models..."
python3 "$TOOLS_DIR/train.py" \
  --dataset-csv "$DATASET_CSV" \
  --out-dir "$MODELS_DIR" \
  --seed "$SEED" \
  --test-size "$TEST_SIZE"

echo "[4/5] Evaluating models..."
python3 "$TOOLS_DIR/evaluate.py" \
  --dataset-csv "$DATASET_CSV" \
  --model-dir "$MODELS_DIR" \
  --seed "$SEED" \
  --test-size "$TEST_SIZE"

echo "[5/5] Exporting ONNX..."
python3 "$TOOLS_DIR/export_onnx.py" \
  --model-dir "$MODELS_DIR" \
  --out-dir "$ONNX_DIR"

if [[ "$COPY_ASSETS" == "1" ]]; then
  mkdir -p "$ROOT_DIR/assets/models"
  cp "$ONNX_DIR/mix_apply_classifier.onnx" "$ROOT_DIR/assets/models/"
  cp "$ONNX_DIR/mix_magnitude_regressor.onnx" "$ROOT_DIR/assets/models/"
  echo "[done] ONNX models copied to assets/models/"
else
  echo "[done] ONNX models exported to: $ONNX_DIR"
fi
