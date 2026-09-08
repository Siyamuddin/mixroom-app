#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  deploy_site.sh \
    --bucket <s3-bucket-name> \
    --site-url <https://admin.example.com/> \
    --api-base-url <https://api-id.execute-api.region.amazonaws.com/stage> \
    --cognito-domain-url <https://your-domain.auth.region.amazoncognito.com> \
    --cognito-client-id <client-id> \
    [--distribution-id <cloudfront-distribution-id>] \
    [--redirect-uri <https://admin.example.com/>] \
    [--logout-uri <https://admin.example.com/>] \
    [--scopes <openid,email>] \
    [--posthog-dashboard-url <https://us.posthog.com/project/...>] \
    [--posthog-embed-url <https://us.posthog.com/shared/...>]
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

js_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "Missing required value: ${name}" >&2
    usage
    exit 1
  fi
}

BUCKET_NAME=""
DISTRIBUTION_ID=""
SITE_URL=""
API_BASE_URL="${MIXROOM_ADMIN_API_BASE_URL:-}"
COGNITO_DOMAIN_URL="${MIXROOM_ADMIN_COGNITO_DOMAIN_URL:-}"
COGNITO_CLIENT_ID="${MIXROOM_ADMIN_COGNITO_CLIENT_ID:-}"
REDIRECT_URI="${MIXROOM_ADMIN_REDIRECT_URI:-}"
LOGOUT_URI="${MIXROOM_ADMIN_LOGOUT_URI:-}"
SCOPES="${MIXROOM_ADMIN_SCOPES:-openid,email}"
POSTHOG_DASHBOARD_URL="${MIXROOM_ADMIN_POSTHOG_DASHBOARD_URL:-}"
POSTHOG_EMBED_URL="${MIXROOM_ADMIN_POSTHOG_EMBED_URL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET_NAME="${2:-}"
      shift 2
      ;;
    --distribution-id)
      DISTRIBUTION_ID="${2:-}"
      shift 2
      ;;
    --site-url)
      SITE_URL="${2:-}"
      shift 2
      ;;
    --api-base-url)
      API_BASE_URL="${2:-}"
      shift 2
      ;;
    --cognito-domain-url)
      COGNITO_DOMAIN_URL="${2:-}"
      shift 2
      ;;
    --cognito-client-id)
      COGNITO_CLIENT_ID="${2:-}"
      shift 2
      ;;
    --redirect-uri)
      REDIRECT_URI="${2:-}"
      shift 2
      ;;
    --logout-uri)
      LOGOUT_URI="${2:-}"
      shift 2
      ;;
    --scopes)
      SCOPES="${2:-}"
      shift 2
      ;;
    --posthog-dashboard-url)
      POSTHOG_DASHBOARD_URL="${2:-}"
      shift 2
      ;;
    --posthog-embed-url)
      POSTHOG_EMBED_URL="${2:-}"
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

require_value "--bucket" "${BUCKET_NAME}"
require_value "--site-url" "${SITE_URL}"
require_value "--api-base-url" "${API_BASE_URL}"
require_value "--cognito-domain-url" "${COGNITO_DOMAIN_URL}"
require_value "--cognito-client-id" "${COGNITO_CLIENT_ID}"

if [[ -z "${REDIRECT_URI}" ]]; then
  REDIRECT_URI="${SITE_URL}"
fi

if [[ -z "${LOGOUT_URI}" ]]; then
  LOGOUT_URI="${SITE_URL}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SITE_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${BUILD_DIR}"
}

trap cleanup EXIT

SCOPES_JSON=""
IFS=',' read -r -a scope_items <<< "${SCOPES}"
for raw_scope in "${scope_items[@]}"; do
  scope="$(trim "${raw_scope}")"
  if [[ -z "${scope}" ]]; then
    continue
  fi
  if [[ -n "${SCOPES_JSON}" ]]; then
    SCOPES_JSON+=", "
  fi
  SCOPES_JSON+="\"$(js_escape "${scope}")\""
done

cp "${SITE_DIR}/index.html" "${BUILD_DIR}/index.html"
cp "${SITE_DIR}/styles.css" "${BUILD_DIR}/styles.css"
cp "${SITE_DIR}/app.js" "${BUILD_DIR}/app.js"
cp "${SITE_DIR}/education-invites.mjs" "${BUILD_DIR}/education-invites.mjs"
cp "${SITE_DIR}/access-duration.mjs" "${BUILD_DIR}/access-duration.mjs"
if [[ -f "${PROJECT_ROOT}/assets/fonts/Pretendard-Regular.otf" ]]; then
  cp "${PROJECT_ROOT}/assets/fonts/Pretendard-Regular.otf" "${BUILD_DIR}/Pretendard-Regular.otf"
fi
if [[ -f "${PROJECT_ROOT}/assets/fonts/Pretendard-SemiBold.otf" ]]; then
  cp "${PROJECT_ROOT}/assets/fonts/Pretendard-SemiBold.otf" "${BUILD_DIR}/Pretendard-SemiBold.otf"
fi
if [[ -f "${PROJECT_ROOT}/assets/fonts/Pretendard-Bold.otf" ]]; then
  cp "${PROJECT_ROOT}/assets/fonts/Pretendard-Bold.otf" "${BUILD_DIR}/Pretendard-Bold.otf"
fi
if [[ -f "${PROJECT_ROOT}/assets/short_white.png" ]]; then
  cp "${PROJECT_ROOT}/assets/short_white.png" "${BUILD_DIR}/mixroom-wordmark.png"
fi
if [[ -f "${PROJECT_ROOT}/assets/mixroom_app_icon_square.png" ]]; then
  cp "${PROJECT_ROOT}/assets/mixroom_app_icon_square.png" "${BUILD_DIR}/mixroom-app-icon.png"
fi

cat > "${BUILD_DIR}/config.js" <<EOF
window.MIXROOM_ADMIN_CONFIG = {
  apiBaseUrl: "$(js_escape "${API_BASE_URL}")",
  cognitoDomainUrl: "$(js_escape "${COGNITO_DOMAIN_URL}")",
  cognitoClientId: "$(js_escape "${COGNITO_CLIENT_ID}")",
  redirectUri: "$(js_escape "${REDIRECT_URI}")",
  logoutUri: "$(js_escape "${LOGOUT_URI}")",
  scopes: [${SCOPES_JSON}],
  posthogDashboardUrl: "$(js_escape "${POSTHOG_DASHBOARD_URL}")",
  posthogEmbedUrl: "$(js_escape "${POSTHOG_EMBED_URL}")",
};
EOF

aws s3 sync "${BUILD_DIR}/" "s3://${BUCKET_NAME}/" \
  --delete \
  --cache-control "public,max-age=300"

# Serve the ES module with a browser-compatible MIME type.
aws s3 cp "${BUILD_DIR}/education-invites.mjs" "s3://${BUCKET_NAME}/education-invites.mjs" \
  --cache-control "public,max-age=300" \
  --content-type "application/javascript"

aws s3 cp "${BUILD_DIR}/access-duration.mjs" "s3://${BUCKET_NAME}/access-duration.mjs" \
  --cache-control "public,max-age=300" \
  --content-type "application/javascript"

# Keep the HTML and runtime configuration fresh so a deployment can point an
# already-open dashboard at versioned JS and CSS assets on its next reload.
aws s3 cp "${BUILD_DIR}/index.html" "s3://${BUCKET_NAME}/index.html" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html"
aws s3 cp "${BUILD_DIR}/config.js" "s3://${BUCKET_NAME}/config.js" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "application/javascript"

if [[ -n "${DISTRIBUTION_ID}" ]]; then
  aws cloudfront create-invalidation \
    --distribution-id "${DISTRIBUTION_ID}" \
    --paths "/*"
fi
