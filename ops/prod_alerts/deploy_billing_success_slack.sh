#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <slack-workspace-id> <slack-channel-id> [stage-name] [region]" >&2
  exit 1
fi

SLACK_WORKSPACE_ID="$1"
SLACK_CHANNEL_ID="$2"
STAGE_NAME="${3:-prod}"
TOPIC_REGION="${4:-ap-northeast-2}"
SLACK_REGION="${5:-us-east-2}"
CLOUDFORMATION_ROLE_ARN="${MIXROOM_CLOUDFORMATION_ROLE_ARN:-arn:aws:iam::353144603233:role/MixroomCloudFormationDeployRole}"

aws cloudformation deploy \
  --stack-name "mixroom-billing-success-topic-${STAGE_NAME}" \
  --template-file ops/prod_alerts/billing_success_topic_stack.yaml \
  --region "${TOPIC_REGION}" \
  --role-arn "${CLOUDFORMATION_ROLE_ARN}" \
  --parameter-overrides "StageName=${STAGE_NAME}"

BILLING_SUCCESS_TOPIC_ARN="arn:aws:sns:${TOPIC_REGION}:353144603233:mixroom-billing-success-${STAGE_NAME}"

aws cloudformation deploy \
  --stack-name "mixroom-billing-success-slack-${STAGE_NAME}" \
  --template-file ops/prod_alerts/billing_success_slack_config_stack.yaml \
  --capabilities CAPABILITY_IAM \
  --region "${SLACK_REGION}" \
  --role-arn "${CLOUDFORMATION_ROLE_ARN}" \
  --parameter-overrides \
    "StageName=${STAGE_NAME}" \
    "BillingSuccessTopicArn=${BILLING_SUCCESS_TOPIC_ARN}" \
    "SlackWorkspaceId=${SLACK_WORKSPACE_ID}" \
    "SlackChannelId=${SLACK_CHANNEL_ID}" \
    "SlackChannelName=development"
