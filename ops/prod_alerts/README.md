# Prod Alerts

This directory holds the low-cost production alerting setup for Mixroom.

Stacks:

- `topic_stack.yaml`: creates the Seoul SNS topic that CloudWatch alarms publish to.
- `slack_config_stack.yaml`: creates the Slack channel configuration after the Slack workspace is authorized.
- `billing_success_topic_stack.yaml`: sends only verified successful purchases to `#development`.

Recommended flow:

1. Deploy `topic_stack.yaml` in `ap-northeast-2`.
2. Deploy the app API and LLM proxy stacks with `AlarmTopicArn` set to that SNS topic ARN.
3. Create a dedicated Slack channel, authorize the workspace once in Amazon Q Developer in chat applications, then deploy `slack_config_stack.yaml` with the workspace/channel IDs.
4. Verify deployed wiring:

   ```bash
   AWS_PROFILE=andrew-admin AWS_DEFAULT_REGION=ap-northeast-2 \
    ops/prod_alerts/verify_prod_alerts.sh
   ```

Successful-purchase notifications use their own SNS topic so CloudWatch alerts
do not mix with commercial activity. Deploy `billing_success_topic_stack.yaml`
with the Slack workspace and `#development` channel IDs, then pass its
`BillingSuccessTopicArn` output to the app API stack's `BillingSuccessTopicArn`
parameter.

Low-cost scope:

- App API `5XXError`
- App API high latency
- Users/auth/entitlements/billing Lambda errors
- Native auth DynamoDB throttle events
- LLM proxy `5xx`
- LLM proxy Lambda errors
- LLM proxy Lambda throttles

This intentionally avoids log-based custom metrics and high-cardinality dimensions.
