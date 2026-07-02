#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  bash tool/deploy_magnitude_model_cdn.sh \
    --stack-name mixroom-magnitude-models-prod \
    [--bucket-name mixroom-magnitude-models-prod] \
    [--prefix magnitude] \
    [--region ap-northeast-2] \
    [--profile andrew-admin]
EOF
}

STACK_NAME=""
BUCKET_NAME=""
PREFIX="magnitude"
REGION="ap-northeast-2"
PROFILE=""
CLOUDFORMATION_ROLE_ARN="${MIXROOM_CLOUDFORMATION_ROLE_ARN:-arn:aws:iam::353144603233:role/MixroomCloudFormationDeployRole}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-name)
      STACK_NAME="${2:-}"
      shift 2
      ;;
    --bucket-name)
      BUCKET_NAME="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:-}"
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

if [[ -z "${STACK_NAME}" ]]; then
  echo "Missing required value: --stack-name" >&2
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${SCRIPT_DIR}/infrastructure/aws_magnitude_models_cdn.template.yaml"

PARAMETERS=(
  "ParameterKey=Prefix,ParameterValue=${PREFIX}"
)

if [[ -n "${BUCKET_NAME}" ]]; then
  PARAMETERS+=("ParameterKey=BucketName,ParameterValue=${BUCKET_NAME}")
fi

AWS_ARGS=(--region "${REGION}")
if [[ -n "${PROFILE}" ]]; then
  AWS_ARGS+=(--profile "${PROFILE}")
fi

aws cloudformation deploy \
  "${AWS_ARGS[@]}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE_PATH}" \
  --role-arn "${CLOUDFORMATION_ROLE_ARN}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "${PARAMETERS[@]}"

aws cloudformation describe-stacks \
  "${AWS_ARGS[@]}" \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' \
  --output table
