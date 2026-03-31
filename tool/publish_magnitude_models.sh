#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  bash tool/publish_magnitude_models.sh \
    --apply-model /path/to/mix_apply_classifier.onnx \
    --magnitude-model /path/to/mix_magnitude_regressor.onnx \
    --bundle-version 2026-03-29-mag-v1 \
    --bucket your-s3-bucket \
    --region ap-northeast-2 \
    --public-base-url https://cdn.example.com/ai-models/magnitude \
    --min-app-version 1.0.9+15 \
    [--distribution-id E123ABC...] \
    [--max-app-version 1.0.9+99] \
    [--rollout-percent 100] \
    [--enabled true] \
    [--prefix magnitude]
EOF
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    exit 1
  fi
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "Missing required value: $name" >&2
    usage
    exit 1
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

APPLY_MODEL=""
MAGNITUDE_MODEL=""
BUNDLE_VERSION=""
BUCKET=""
REGION=""
PUBLIC_BASE_URL=""
MIN_APP_VERSION=""
MAX_APP_VERSION=""
DISTRIBUTION_ID=""
ROLLOUT_PERCENT="100"
ENABLED="true"
PREFIX="magnitude"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply-model)
      APPLY_MODEL="${2:-}"
      shift 2
      ;;
    --magnitude-model)
      MAGNITUDE_MODEL="${2:-}"
      shift 2
      ;;
    --bundle-version)
      BUNDLE_VERSION="${2:-}"
      shift 2
      ;;
    --bucket)
      BUCKET="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --public-base-url)
      PUBLIC_BASE_URL="${2:-}"
      shift 2
      ;;
    --min-app-version)
      MIN_APP_VERSION="${2:-}"
      shift 2
      ;;
    --distribution-id)
      DISTRIBUTION_ID="${2:-}"
      shift 2
      ;;
    --max-app-version)
      MAX_APP_VERSION="${2:-}"
      shift 2
      ;;
    --rollout-percent)
      ROLLOUT_PERCENT="${2:-}"
      shift 2
      ;;
    --enabled)
      ENABLED="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_value "--apply-model" "$APPLY_MODEL"
require_value "--magnitude-model" "$MAGNITUDE_MODEL"
require_value "--bundle-version" "$BUNDLE_VERSION"
require_value "--bucket" "$BUCKET"
require_value "--region" "$REGION"
require_value "--public-base-url" "$PUBLIC_BASE_URL"
require_value "--min-app-version" "$MIN_APP_VERSION"

require_file "$APPLY_MODEL"
require_file "$MAGNITUDE_MODEL"

APPLY_BASENAME="$(basename "$APPLY_MODEL")"
MAG_BASENAME="$(basename "$MAGNITUDE_MODEL")"
APPLY_VERSION="${APPLY_BASENAME%.*}"
MAG_VERSION="${MAG_BASENAME%.*}"
APPLY_SHA="$(sha256_file "$APPLY_MODEL")"
MAG_SHA="$(sha256_file "$MAGNITUDE_MODEL")"

PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
PREFIX="${PREFIX#/}"
PREFIX="${PREFIX%/}"
S3_PREFIX="s3://${BUCKET}/${PREFIX}/${BUNDLE_VERSION}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

MANIFEST_PATH="${TMP_DIR}/manifest.json"

python3 - <<'PY' "$MANIFEST_PATH" \
  "$BUNDLE_VERSION" "$ENABLED" "$ROLLOUT_PERCENT" "$MIN_APP_VERSION" "$MAX_APP_VERSION" \
  "$APPLY_VERSION" "$PUBLIC_BASE_URL" "$APPLY_BASENAME" "$APPLY_SHA" \
  "$MAG_VERSION" "$MAG_BASENAME" "$MAG_SHA"
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
bundle_version = sys.argv[2]
enabled = sys.argv[3].lower() == "true"
rollout_percent = int(sys.argv[4])
min_app_version = sys.argv[5]
max_app_version = sys.argv[6]
apply_version = sys.argv[7]
public_base_url = sys.argv[8].rstrip("/")
apply_basename = sys.argv[9]
apply_sha = sys.argv[10]
mag_version = sys.argv[11]
mag_basename = sys.argv[12]
mag_sha = sys.argv[13]

data = {
    "bundle_version": bundle_version,
    "enabled": enabled,
    "rollout_percent": rollout_percent,
    "min_app_version": min_app_version,
    "max_app_version": max_app_version,
    "apply_model": {
        "version": apply_version,
        "url": f"{public_base_url}/{bundle_version}/{apply_basename}",
        "sha256": apply_sha,
        "file_name": apply_basename,
    },
    "magnitude_model": {
        "version": mag_version,
        "url": f"{public_base_url}/{bundle_version}/{mag_basename}",
        "sha256": mag_sha,
        "file_name": mag_basename,
    },
}

path.write_text(json.dumps(data, indent=2) + "\n")
PY

aws s3 cp "$APPLY_MODEL" "${S3_PREFIX}/${APPLY_BASENAME}" \
  --region "$REGION" \
  --content-type application/octet-stream \
  --cache-control "public,max-age=31536000,immutable"

aws s3 cp "$MAGNITUDE_MODEL" "${S3_PREFIX}/${MAG_BASENAME}" \
  --region "$REGION" \
  --content-type application/octet-stream \
  --cache-control "public,max-age=31536000,immutable"

aws s3 cp "$MANIFEST_PATH" "s3://${BUCKET}/${PREFIX}/manifest.json" \
  --region "$REGION" \
  --content-type application/json \
  --cache-control "public,max-age=60"

if [[ -n "${DISTRIBUTION_ID}" ]]; then
  aws cloudfront create-invalidation \
    --distribution-id "${DISTRIBUTION_ID}" \
    --paths "/${PREFIX}/manifest.json"
fi

cat <<EOF
Published magnitude model bundle.

Bundle version:
  ${BUNDLE_VERSION}

Manifest URL:
  ${PUBLIC_BASE_URL}/manifest.json

Build flag:
  --dart-define=MIXROOM_MAGNITUDE_MODEL_MANIFEST_URL=${PUBLIC_BASE_URL}/manifest.json

Uploaded files:
  s3://${BUCKET}/${PREFIX}/${BUNDLE_VERSION}/${APPLY_BASENAME}
  s3://${BUCKET}/${PREFIX}/${BUNDLE_VERSION}/${MAG_BASENAME}
  s3://${BUCKET}/${PREFIX}/manifest.json
EOF
