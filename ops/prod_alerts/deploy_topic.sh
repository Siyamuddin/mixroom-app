#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-mixroom-prod-alerts-topic}"
STAGE_NAME="${2:-prod}"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
CLOUDFORMATION_ROLE_ARN="${MIXROOM_CLOUDFORMATION_ROLE_ARN:-arn:aws:iam::353144603233:role/MixroomCloudFormationDeployRole}"

aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file ops/prod_alerts/topic_stack.yaml \
  --capabilities CAPABILITY_IAM \
  --region "${REGION}" \
  --role-arn "${CLOUDFORMATION_ROLE_ARN}" \
  --parameter-overrides "StageName=${STAGE_NAME}"

aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AlertTopicArn'].OutputValue" \
  --output text
