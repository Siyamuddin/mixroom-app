#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
APP_API_STACK="${APP_API_STACK:-mixroom-app-api-prod}"
LLM_PROXY_STACK="${LLM_PROXY_STACK:-mixroom-llm-proxy-prod}"
ALERT_TOPIC_ARN="${ALERT_TOPIC_ARN:-arn:aws:sns:ap-northeast-2:353144603233:mixroom-prod-alerts-prod}"

describe_stack_alarm_topic() {
  local stack_name="$1"
  aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${stack_name}" \
    --query "Stacks[0].Parameters[?ParameterKey=='AlarmTopicArn'].ParameterValue | [0]" \
    --output text
}

count_stack_alarms() {
  local stack_name="$1"
  aws cloudwatch describe-alarms \
    --region "${REGION}" \
    --query "length(MetricAlarms[?contains(AlarmName, '${stack_name}')])" \
    --output text
}

count_topic_subscriptions() {
  aws sns list-subscriptions-by-topic \
    --region "${REGION}" \
    --topic-arn "${ALERT_TOPIC_ARN}" \
    --query "length(Subscriptions[])" \
    --output text
}

echo "Region: ${REGION}"
echo "Alert topic: ${ALERT_TOPIC_ARN}"

app_api_topic="$(describe_stack_alarm_topic "${APP_API_STACK}")"
llm_proxy_topic="$(describe_stack_alarm_topic "${LLM_PROXY_STACK}")"
app_api_alarm_count="$(count_stack_alarms "${APP_API_STACK}")"
llm_proxy_alarm_count="$(count_stack_alarms "${LLM_PROXY_STACK}")"
subscription_count="$(count_topic_subscriptions)"

echo "App API AlarmTopicArn: ${app_api_topic}"
echo "LLM proxy AlarmTopicArn: ${llm_proxy_topic}"
echo "App API alarm count: ${app_api_alarm_count}"
echo "LLM proxy alarm count: ${llm_proxy_alarm_count}"
echo "SNS subscription count: ${subscription_count}"

if [[ "${app_api_topic}" != "${ALERT_TOPIC_ARN}" ]]; then
  echo "App API stack is not wired to the expected alert topic." >&2
  exit 1
fi

if [[ "${llm_proxy_topic}" != "${ALERT_TOPIC_ARN}" ]]; then
  echo "LLM proxy stack is not wired to the expected alert topic." >&2
  exit 1
fi

if [[ "${app_api_alarm_count}" -lt 1 ]]; then
  echo "No App API CloudWatch alarms found." >&2
  exit 1
fi

if [[ "${llm_proxy_alarm_count}" -lt 1 ]]; then
  echo "No LLM proxy CloudWatch alarms found." >&2
  exit 1
fi

if [[ "${subscription_count}" -lt 1 ]]; then
  echo "Alert SNS topic has no subscriptions." >&2
  exit 1
fi

echo "Production alert wiring looks present."
