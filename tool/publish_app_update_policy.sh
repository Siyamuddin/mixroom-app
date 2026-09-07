#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  bash tool/publish_app_update_policy.sh \
    --input docs/app_update_policy.example.json \
    --bucket your-static-config-bucket \
    --region ap-northeast-2 \
    --public-base-url https://cdn.example.com/app-update \
    [--distribution-id E123ABC...] \
    [--prefix app-update]
EOF
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

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    exit 1
  fi
}

INPUT=""
BUCKET=""
REGION=""
PUBLIC_BASE_URL=""
DISTRIBUTION_ID=""
PREFIX="app-update"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="${2:-}"
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
    --distribution-id)
      DISTRIBUTION_ID="${2:-}"
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

require_value "--input" "$INPUT"
require_value "--bucket" "$BUCKET"
require_value "--region" "$REGION"
require_value "--public-base-url" "$PUBLIC_BASE_URL"
require_file "$INPUT"

python3 - <<'PY' "$INPUT"
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open("r", encoding="utf-8") as fh:
    decoded = json.load(fh)

if not isinstance(decoded, dict):
    raise SystemExit("Policy root must be an object")

for platform in ("ios", "android", "macos"):
    payload = decoded.get(platform)
    if payload is None:
        continue
    if not isinstance(payload, dict):
        raise SystemExit(f"{platform} policy must be an object")
    latest = str(payload.get("latestVersion", "")).strip()
    minimum = str(payload.get("minSupportedVersion", "")).strip()
    cadence = payload.get("promptCadenceHours", 24)
    if not latest:
      raise SystemExit(f"{platform}.latestVersion is required when {platform} is present")
    if minimum and minimum == latest:
      pass
    if not isinstance(cadence, int):
      raise SystemExit(f"{platform}.promptCadenceHours must be an integer")
PY

PREFIX="${PREFIX#/}"
PREFIX="${PREFIX%/}"
TARGET_KEY="${PREFIX}/version-policy.json"
TARGET_URI="s3://${BUCKET}/${TARGET_KEY}"

aws s3 cp \
  "$INPUT" \
  "$TARGET_URI" \
  --region "$REGION" \
  --content-type application/json \
  --cache-control "public, max-age=300"

if [[ -n "$DISTRIBUTION_ID" ]]; then
  aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths "/${TARGET_KEY}"
fi

echo "Published app update policy:"
echo "  ${PUBLIC_BASE_URL%/}/version-policy.json"
