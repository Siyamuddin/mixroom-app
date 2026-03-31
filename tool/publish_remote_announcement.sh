#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  bash tool/publish_remote_announcement.sh \
    --announcement-version 2026-03-29-announcement-v1 \
    --bucket mixroom-magnitude-models-prod \
    --region ap-northeast-2 \
    --public-base-url https://d22u50embnfa6f.cloudfront.net/announcements \
    [--distribution-id E123ABC...] \
    [--prefix announcements] \
    [--presentation-mode banner|modal|both] \
    [--title "Mixroom update"] \
    [--body "We shipped something new."] \
    [--primary-label "Learn more"] \
    [--secondary-label "Dismiss"] \
    [--primary-action-url https://mixroom.ai/updates] \
    [--style info|success|warning|critical] \
    [--media-file /path/to/announcement.png] \
    [--min-app-version 1.0.9+15] \
    [--max-app-version 1.0.9+99] \
    [--rollout-percent 100] \
    [--min-account-created-at 2026-03-29T00:00:00Z] \
    [--max-account-created-at 2026-04-30T23:59:59Z] \
    [--disable]
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

ANNOUNCEMENT_VERSION=""
BUCKET=""
REGION=""
PUBLIC_BASE_URL=""
PREFIX="announcements"
DISTRIBUTION_ID=""
PRESENTATION_MODE="banner"
TITLE="Mixroom update"
BODY=""
PRIMARY_LABEL="Learn more"
SECONDARY_LABEL="Dismiss"
PRIMARY_ACTION_URL=""
STYLE="info"
MEDIA_FILE=""
MIN_APP_VERSION=""
MAX_APP_VERSION=""
ROLLOUT_PERCENT="100"
MIN_ACCOUNT_CREATED_AT=""
MAX_ACCOUNT_CREATED_AT=""
ENABLED="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --announcement-version)
      ANNOUNCEMENT_VERSION="${2:-}"
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
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --distribution-id)
      DISTRIBUTION_ID="${2:-}"
      shift 2
      ;;
    --presentation-mode)
      PRESENTATION_MODE="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body)
      BODY="${2:-}"
      shift 2
      ;;
    --primary-label)
      PRIMARY_LABEL="${2:-}"
      shift 2
      ;;
    --secondary-label)
      SECONDARY_LABEL="${2:-}"
      shift 2
      ;;
    --primary-action-url)
      PRIMARY_ACTION_URL="${2:-}"
      shift 2
      ;;
    --style)
      STYLE="${2:-}"
      shift 2
      ;;
    --media-file)
      MEDIA_FILE="${2:-}"
      shift 2
      ;;
    --min-app-version)
      MIN_APP_VERSION="${2:-}"
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
    --min-account-created-at)
      MIN_ACCOUNT_CREATED_AT="${2:-}"
      shift 2
      ;;
    --max-account-created-at)
      MAX_ACCOUNT_CREATED_AT="${2:-}"
      shift 2
      ;;
    --disable)
      ENABLED="false"
      shift 1
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

require_value "--announcement-version" "$ANNOUNCEMENT_VERSION"
require_value "--bucket" "$BUCKET"
require_value "--region" "$REGION"
require_value "--public-base-url" "$PUBLIC_BASE_URL"

if [[ "$PRESENTATION_MODE" != "banner" &&
      "$PRESENTATION_MODE" != "modal" &&
      "$PRESENTATION_MODE" != "both" ]]; then
  echo "Unsupported --presentation-mode: $PRESENTATION_MODE" >&2
  exit 1
fi

if [[ "$STYLE" != "info" &&
      "$STYLE" != "success" &&
      "$STYLE" != "warning" &&
      "$STYLE" != "critical" ]]; then
  echo "Unsupported --style: $STYLE" >&2
  exit 1
fi

MEDIA_BASENAME=""
MEDIA_VERSION=""
MEDIA_SHA=""
CONTENT_TYPE=""

if [[ -n "$MEDIA_FILE" ]]; then
  require_file "$MEDIA_FILE"
  MEDIA_BASENAME="$(basename "$MEDIA_FILE")"
  MEDIA_VERSION="${MEDIA_BASENAME%.*}"
  MEDIA_SHA="$(sha256_file "$MEDIA_FILE")"
  case "${MEDIA_BASENAME##*.}" in
    png) CONTENT_TYPE="image/png" ;;
    jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
    webp) CONTENT_TYPE="image/webp" ;;
    gif) CONTENT_TYPE="image/gif" ;;
    *)
      echo "Unsupported announcement media extension: ${MEDIA_BASENAME##*.}" >&2
      exit 1
      ;;
  esac
fi

PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
PREFIX="${PREFIX#/}"
PREFIX="${PREFIX%/}"
S3_PREFIX="s3://${BUCKET}/${PREFIX}/${ANNOUNCEMENT_VERSION}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

MANIFEST_PATH="${TMP_DIR}/manifest.json"

python3 - <<'PY' "$MANIFEST_PATH" \
  "$ANNOUNCEMENT_VERSION" "$ENABLED" "$ROLLOUT_PERCENT" "$MIN_APP_VERSION" "$MAX_APP_VERSION" \
  "$PRESENTATION_MODE" "$STYLE" "$TITLE" "$BODY" "$PRIMARY_LABEL" "$SECONDARY_LABEL" "$PRIMARY_ACTION_URL" \
  "$MIN_ACCOUNT_CREATED_AT" "$MAX_ACCOUNT_CREATED_AT" \
  "$PUBLIC_BASE_URL" "$MEDIA_BASENAME" "$MEDIA_SHA" "$MEDIA_VERSION"
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
announcement_version = sys.argv[2]
enabled = sys.argv[3].lower() == "true"
rollout_percent = int(sys.argv[4])
min_app_version = sys.argv[5]
max_app_version = sys.argv[6]
presentation_mode = sys.argv[7]
style = sys.argv[8]
title = sys.argv[9]
body = sys.argv[10]
primary_label = sys.argv[11]
secondary_label = sys.argv[12]
primary_action_url = sys.argv[13]
min_account_created_at = sys.argv[14]
max_account_created_at = sys.argv[15]
public_base_url = sys.argv[16].rstrip("/")
media_basename = sys.argv[17]
media_sha = sys.argv[18]
media_version = sys.argv[19]

data = {
    "announcement_version": announcement_version,
    "enabled": enabled,
    "rollout_percent": rollout_percent,
    "min_app_version": min_app_version,
    "max_app_version": max_app_version,
    "presentation_mode": presentation_mode,
    "style": style,
    "title": title,
    "body": body,
    "primary_button_label": primary_label,
    "secondary_button_label": secondary_label,
    "primary_action_url": primary_action_url,
    "min_account_created_at": min_account_created_at,
    "max_account_created_at": max_account_created_at,
}

if enabled and media_basename:
    data["media"] = {
        "media_type": "image",
        "url": f"{public_base_url}/{announcement_version}/{media_basename}",
        "sha256": media_sha,
        "file_name": media_basename,
        "version": media_version,
    }

path.write_text(json.dumps(data, indent=2) + "\n")
PY

if [[ "$ENABLED" == "true" && -n "$MEDIA_FILE" ]]; then
  aws s3 cp "$MEDIA_FILE" "${S3_PREFIX}/${MEDIA_BASENAME}" \
    --region "$REGION" \
    --content-type "$CONTENT_TYPE" \
    --cache-control "public,max-age=31536000,immutable"
fi

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
Published remote announcement.

Announcement version:
  ${ANNOUNCEMENT_VERSION}

Manifest URL:
  ${PUBLIC_BASE_URL}/manifest.json

Enabled:
  ${ENABLED}
EOF
