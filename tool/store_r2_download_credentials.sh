#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE_NAME="${AWS_PROFILE:-andrew-admin}"
AWS_REGION_NAME="${AWS_REGION:-ap-northeast-2}"
ACCESS_KEY_PARAMETER="/mixroom/prod/r2/downloads/access-key-id"
SECRET_KEY_PARAMETER="/mixroom/prod/r2/downloads/secret-access-key"

cleanup() {
  unset r2_access_key_id r2_secret_access_key
}
trap cleanup EXIT

read -r -p "R2 Access Key ID: " r2_access_key_id
read -r -s -p "R2 Secret Access Key: " r2_secret_access_key
echo

[[ -n "$r2_access_key_id" ]] || {
  echo "error: Access Key ID cannot be empty." >&2
  exit 1
}
[[ -n "$r2_secret_access_key" ]] || {
  echo "error: Secret Access Key cannot be empty." >&2
  exit 1
}

AWS_PROFILE="$AWS_PROFILE_NAME" AWS_DEFAULT_REGION="$AWS_REGION_NAME" \
  aws ssm put-parameter \
    --name "$ACCESS_KEY_PARAMETER" \
    --type SecureString \
    --value "$r2_access_key_id" \
    --overwrite >/dev/null

AWS_PROFILE="$AWS_PROFILE_NAME" AWS_DEFAULT_REGION="$AWS_REGION_NAME" \
  aws ssm put-parameter \
    --name "$SECRET_KEY_PARAMETER" \
    --type SecureString \
    --value "$r2_secret_access_key" \
    --overwrite >/dev/null

echo "Stored the downloads-bucket R2 credentials in AWS SSM."
