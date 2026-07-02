#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
STACK_NAME="${MIXROOM_PROD_WAF_STACK_NAME:-mixroom-prod-api-waf}"
WEB_ACL_NAME="${MIXROOM_PROD_WAF_NAME:-mixroom-prod-apis}"
STAGE_NAME="${MIXROOM_STAGE_NAME:-prod}"
CLOUDFORMATION_ROLE_ARN="${MIXROOM_CLOUDFORMATION_ROLE_ARN:-arn:aws:iam::353144603233:role/MixroomCloudFormationDeployRole}"

aws cloudformation deploy \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${SCRIPT_DIR}/api_web_acl_stack.yaml" \
  --role-arn "${CLOUDFORMATION_ROLE_ARN}" \
  --parameter-overrides \
    StageName="${STAGE_NAME}" \
    WebAclName="${WEB_ACL_NAME}"

aws cloudformation describe-stacks \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='WebAclArn'].OutputValue" \
  --output text
