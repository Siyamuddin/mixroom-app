#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_R2_BUCKET="mixroom-downloads-prod"
DEFAULT_R2_ACCOUNT_ID="4b907b155366fa8b00120bffa3a6f8b2"
DEFAULT_R2_ACCESS_KEY_PARAMETER="/mixroom/prod/r2/downloads/access-key-id"
DEFAULT_R2_SECRET_KEY_PARAMETER="/mixroom/prod/r2/downloads/secret-access-key"
DEFAULT_PUBLIC_ORIGIN="https://www.mixroom.ai/downloads"
DEFAULT_POLICY_BUCKET="mixroom-magnitude-models-prod"
DEFAULT_POLICY_REGION="ap-northeast-2"
DEFAULT_POLICY_DISTRIBUTION_ID="E9GVRRNS9G2HJ"

ZIP_PATH="$ROOT_DIR/build/distribution/Mixroom-macOS.zip"
DMG_PATH="$ROOT_DIR/build/distribution/Mixroom-macOS.dmg"
R2_BUCKET="$DEFAULT_R2_BUCKET"
R2_ENDPOINT="${MIXROOM_R2_ENDPOINT_URL:-}"
R2_ACCOUNT_ID="${MIXROOM_R2_ACCOUNT_ID:-$DEFAULT_R2_ACCOUNT_ID}"
R2_ACCESS_KEY_ID="${MIXROOM_R2_ACCESS_KEY_ID:-}"
R2_SECRET_ACCESS_KEY="${MIXROOM_R2_SECRET_ACCESS_KEY:-}"
R2_ACCESS_KEY_PARAMETER="${MIXROOM_R2_ACCESS_KEY_PARAMETER:-$DEFAULT_R2_ACCESS_KEY_PARAMETER}"
R2_SECRET_KEY_PARAMETER="${MIXROOM_R2_SECRET_KEY_PARAMETER:-$DEFAULT_R2_SECRET_KEY_PARAMETER}"
PUBLIC_ORIGIN="$DEFAULT_PUBLIC_ORIGIN"
POLICY_BUCKET="$DEFAULT_POLICY_BUCKET"
POLICY_REGION="$DEFAULT_POLICY_REGION"
POLICY_DISTRIBUTION_ID="$DEFAULT_POLICY_DISTRIBUTION_ID"
VERSION=""
BUILD_NUMBER=""
RELEASE_NOTES_URL=""
MIN_SUPPORTED_VERSION=""
PROMPT_CADENCE_HOURS="24"

usage() {
  cat >&2 <<'EOF'
Usage:
  AWS_PROFILE=andrew-admin \
  bash tool/publish_macos_update.sh \
    --version 1.3.7 \
    --build-number 55 \
    [--release-notes-url https://mixroom.ai/releases/1.3.7] \
    [--min-supported-version 1.3.6]

Defaults:
  --zip                  build/distribution/Mixroom-macOS.zip
  --dmg                  build/distribution/Mixroom-macOS.dmg
  --r2-bucket            mixroom-downloads-prod
  --public-origin        https://www.mixroom.ai/downloads
  --policy-bucket        mixroom-magnitude-models-prod
  --policy-region        ap-northeast-2
  --policy-distribution  E9GVRRNS9G2HJ

The script publishes to Cloudflare R2:
  mac/releases/<version+build>/Mixroom-<version+build>-macOS.zip
  mac/appcast.xml
  mac/Mixroom-macOS.dmg

It keeps the existing cross-platform version-policy.json on AWS CloudFront.
R2 S3 credentials are loaded from these AWS SSM parameters:
  /mixroom/prod/r2/downloads/access-key-id
  /mixroom/prod/r2/downloads/secret-access-key
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:-}"; shift 2 ;;
    --zip) ZIP_PATH="${2:-}"; shift 2 ;;
    --dmg) DMG_PATH="${2:-}"; shift 2 ;;
    --r2-bucket) R2_BUCKET="${2:-}"; shift 2 ;;
    --r2-endpoint) R2_ENDPOINT="${2:-}"; shift 2 ;;
    --public-origin) PUBLIC_ORIGIN="${2:-}"; shift 2 ;;
    --policy-bucket) POLICY_BUCKET="${2:-}"; shift 2 ;;
    --policy-region) POLICY_REGION="${2:-}"; shift 2 ;;
    --policy-distribution) POLICY_DISTRIBUTION_ID="${2:-}"; shift 2 ;;
    --release-notes-url) RELEASE_NOTES_URL="${2:-}"; shift 2 ;;
    --min-supported-version) MIN_SUPPORTED_VERSION="${2:-}"; shift 2 ;;
    --prompt-cadence-hours) PROMPT_CADENCE_HOURS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "--version must be a semantic version such as 1.3.7."
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] \
  || fail "--build-number must be a positive integer."
[[ "$PROMPT_CADENCE_HOURS" =~ ^[1-9][0-9]*$ ]] \
  || fail "--prompt-cadence-hours must be a positive integer."
if [[ -n "$MIN_SUPPORTED_VERSION" ]]; then
  [[ "$MIN_SUPPORTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
    || fail "--min-supported-version must be a semantic version."
fi
[[ -f "$ZIP_PATH" ]] || fail "Sparkle ZIP not found: $ZIP_PATH"
[[ -f "$DMG_PATH" ]] || fail "DMG not found: $DMG_PATH"

if [[ -z "$R2_ENDPOINT" ]]; then
  R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
fi

if [[ -z "$R2_ACCESS_KEY_ID" ]]; then
  R2_ACCESS_KEY_ID="$(aws ssm get-parameter \
    --name "$R2_ACCESS_KEY_PARAMETER" \
    --query Parameter.Value \
    --output text \
    --region "$POLICY_REGION")" \
    || fail "Could not load the R2 access key ID from AWS SSM."
fi
if [[ -z "$R2_SECRET_ACCESS_KEY" ]]; then
  R2_SECRET_ACCESS_KEY="$(aws ssm get-parameter \
    --name "$R2_SECRET_KEY_PARAMETER" \
    --with-decryption \
    --query Parameter.Value \
    --output text \
    --region "$POLICY_REGION")" \
    || fail "Could not load the R2 secret access key from AWS SSM."
fi
[[ -n "$R2_ACCESS_KEY_ID" ]] || fail "The R2 access key ID is empty."
[[ -n "$R2_SECRET_ACCESS_KEY" ]] || fail "The R2 secret access key is empty."

SIGN_TOOL="$ROOT_DIR/macos/Pods/Sparkle/bin/sign_update"
[[ -x "$SIGN_TOOL" ]] \
  || fail "Sparkle sign_update is missing. Run: flutter build macos --config-only"

SIGN_OUTPUT="$($SIGN_TOOL "$ZIP_PATH")"
SIGNATURE="$(/usr/bin/sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGN_OUTPUT")"
ARCHIVE_LENGTH="$(/usr/bin/sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIGN_OUTPUT")"
[[ -n "$SIGNATURE" && -n "$ARCHIVE_LENGTH" ]] \
  || fail "Could not parse Sparkle signature output."

PUBLIC_ORIGIN="${PUBLIC_ORIGIN%/}"
RELEASE_ID="${VERSION}+${BUILD_NUMBER}"
ZIP_NAME="Mixroom-${RELEASE_ID}-macOS.zip"
ZIP_KEY="mac/releases/${RELEASE_ID}/${ZIP_NAME}"
APPCAST_KEY="mac/appcast.xml"
DMG_KEY="mac/Mixroom-macOS.dmg"
PUBLIC_ZIP_PATH="releases/${RELEASE_ID}/${ZIP_NAME}"
PUBLIC_APPCAST_PATH="appcast.xml"
PUBLIC_DMG_PATH="Mixroom-macOS.dmg"
POLICY_KEY="app-update/version-policy.json"
APPCAST_PATH="$ROOT_DIR/build/distribution/appcast.xml"
POLICY_PATH="$ROOT_DIR/build/distribution/version-policy.json"
PUB_DATE="$(LC_ALL=C /bin/date -u '+%a, %d %b %Y %H:%M:%S +0000')"

RELEASE_NOTES_ELEMENT=""
if [[ -n "$RELEASE_NOTES_URL" ]]; then
  RELEASE_NOTES_ELEMENT="<sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>"
fi

/bin/mkdir -p "$(/usr/bin/dirname "$APPCAST_PATH")"
/bin/cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mixroom macOS Updates</title>
    <link>${PUBLIC_ORIGIN}/${PUBLIC_APPCAST_PATH}</link>
    <description>Production updates for the direct-download Mixroom macOS app.</description>
    <language>en</language>
    <item>
      <title>Mixroom ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      ${RELEASE_NOTES_ELEMENT}
      <enclosure
        url="${PUBLIC_ORIGIN}/${PUBLIC_ZIP_PATH}"
        sparkle:edSignature="${SIGNATURE}"
        sparkle:os="macos"
        length="${ARCHIVE_LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

/usr/bin/plutil -lint "$ROOT_DIR/macos/Runner/Info.plist" >/dev/null

r2_aws() {
  AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  AWS_DEFAULT_REGION=auto \
    aws --endpoint-url "$R2_ENDPOINT" "$@"
}

r2_aws s3 cp "$ZIP_PATH" "s3://${R2_BUCKET}/${ZIP_KEY}" \
  --content-type application/zip \
  --cache-control "public, max-age=31536000, immutable"

r2_aws s3 cp "$APPCAST_PATH" "s3://${R2_BUCKET}/${APPCAST_KEY}" \
  --content-type application/rss+xml \
  --cache-control "no-cache, max-age=0, must-revalidate"

r2_aws s3 cp "$DMG_PATH" "s3://${R2_BUCKET}/${DMG_KEY}" \
  --content-type application/x-apple-diskimage \
  --content-disposition 'attachment; filename="Mixroom-macOS.dmg"' \
  --cache-control "public, max-age=300, must-revalidate"

# Keep the existing mobile/desktop version badge policy on its current AWS
# origin. Sparkle independently trusts only its signed appcast and archive.
aws s3 cp "s3://${POLICY_BUCKET}/${POLICY_KEY}" "$POLICY_PATH" \
  --region "$POLICY_REGION"
python3 - "$POLICY_PATH" "$VERSION" "$MIN_SUPPORTED_VERSION" "$PROMPT_CADENCE_HOURS" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["macos"] = {
    "latestVersion": sys.argv[2],
    "minSupportedVersion": sys.argv[3],
    "promptCadenceHours": int(sys.argv[4]),
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
aws s3 cp "$POLICY_PATH" "s3://${POLICY_BUCKET}/${POLICY_KEY}" \
  --region "$POLICY_REGION" \
  --content-type application/json \
  --cache-control "public, max-age=300"

if [[ -n "$POLICY_DISTRIBUTION_ID" ]]; then
  aws cloudfront create-invalidation \
    --distribution-id "$POLICY_DISTRIBUTION_ID" \
    --paths "/${POLICY_KEY}" >/dev/null
fi

echo "Published Mixroom ${RELEASE_ID}:"
echo "  Website DMG: ${PUBLIC_ORIGIN}/${PUBLIC_DMG_PATH}"
echo "  Sparkle feed: ${PUBLIC_ORIGIN}/${PUBLIC_APPCAST_PATH}"
echo "  Update ZIP: ${PUBLIC_ORIGIN}/${PUBLIC_ZIP_PATH}"
