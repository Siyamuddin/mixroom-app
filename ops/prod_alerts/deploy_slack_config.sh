#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <alert-topic-arn> <slack-workspace-id> <slack-channel-id> <slack-channel-name> [stack-name] [stage-name] [region]" >&2
  exit 1
fi

ALERT_TOPIC_ARN="$1"
SLACK_WORKSPACE_ID="$2"
SLACK_CHANNEL_ID="$3"
SLACK_CHANNEL_NAME="$4"
STACK_NAME="${5:-mixroom-prod-alerts-slack}"
STAGE_NAME="${6:-prod}"
REGION="${7:-us-east-2}"
CLOUDFORMATION_ROLE_ARN="${MIXROOM_CLOUDFORMATION_ROLE_ARN:-arn:aws:iam::353144603233:role/MixroomCloudFormationDeployRole}"

aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file ops/prod_alerts/slack_config_stack.yaml \
  --capabilities CAPABILITY_IAM \
  --region "${REGION}" \
  --role-arn "${CLOUDFORMATION_ROLE_ARN}" \
  --parameter-overrides \
    "StageName=${STAGE_NAME}" \
    "AlertTopicArn=${ALERT_TOPIC_ARN}" \
    "SlackWorkspaceId=${SLACK_WORKSPACE_ID}" \
    "SlackChannelId=${SLACK_CHANNEL_ID}" \
    "SlackChannelName=${SLACK_CHANNEL_NAME}"
