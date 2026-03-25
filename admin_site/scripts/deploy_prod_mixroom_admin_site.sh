#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUCKET_NAME="${MIXROOM_ADMIN_PROD_BUCKET:-mixroom-admin-site-prod}"
DISTRIBUTION_ID="${MIXROOM_ADMIN_PROD_DISTRIBUTION_ID:-E3MDYRCBQBRFKH}"
SITE_URL="${MIXROOM_ADMIN_PROD_SITE_URL:-https://admin.mixroom.ai/}"
API_BASE_URL="${MIXROOM_ADMIN_API_BASE_URL:-https://guepfr96ah.execute-api.ap-northeast-2.amazonaws.com/prod}"
COGNITO_DOMAIN_URL="${MIXROOM_ADMIN_COGNITO_DOMAIN_URL:-https://ap-northeast-2wpqpelcma.auth.ap-northeast-2.amazoncognito.com}"
COGNITO_CLIENT_ID="${MIXROOM_ADMIN_COGNITO_CLIENT_ID:-6r47qhuq89m6jv59phca7u1itd}"

exec "${SCRIPT_DIR}/deploy_site.sh" \
  --bucket "${BUCKET_NAME}" \
  --distribution-id "${DISTRIBUTION_ID}" \
  --site-url "${SITE_URL}" \
  --api-base-url "${API_BASE_URL}" \
  --cognito-domain-url "${COGNITO_DOMAIN_URL}" \
  --cognito-client-id "${COGNITO_CLIENT_ID}" \
  "$@"
