# Mixroom Subscription Backend (AWS)

This package is the in-house subscription core that normalizes Apple IAP, Google IAP, Paddle, and Toss into one canonical entitlement record per Cognito user.

## What is implemented

- Canonical domain model for plans/providers/statuses.
- Client APIs:
  - `GET /v1/entitlements/me`
  - `POST /v1/billing/web/checkout-session`
  - `POST /v1/billing/mobile/apple/verify`
  - `POST /v1/billing/mobile/google/verify`
  - `POST /v1/billing/restore`
  - `GET /v1/billing/portal-url`
- Webhook ingestion:
  - `POST /v1/webhooks/apple`
  - `POST /v1/webhooks/google`
  - `POST /v1/webhooks/paddle`
  - `POST /v1/webhooks/toss`
- Idempotent billing event storage and projection queue.
- Projection worker to update `subscriptions` + `entitlements_current`.
- Scheduled reconciliation worker.
- SAM infrastructure template with DynamoDB/SQS/Lambda/API/EventBridge.

## Repo layout

- `template.yaml`: SAM stack definition.
- `openapi.yaml`: API contract reference.
- `src/common/`: config, repository, model helpers.
- `src/handlers/`: Lambda entry points.

## Deploy (SAM)

```bash
cd backend/subscriptions
sam build
sam deploy --guided
```

## Required environment and secrets

Environment variables (set by template and per-stage overrides):

- `BILLING_EVENTS_TABLE`
- `SUBSCRIPTIONS_TABLE`
- `ENTITLEMENTS_TABLE`
- `CATALOG_MAPPINGS_TABLE`
- `CUSTOMER_LINKS_TABLE`
- `PURCHASE_TOKENS_TABLE`
- `RECONCILIATION_JOBS_TABLE`
- `PROJECTION_QUEUE_URL`
- `AWS_REGION`
- `ENFORCE_SUBSCRIPTIONS`
- `ALLOW_STUDIO_TIER`

Provider secrets should be stored in Secrets Manager and read by handlers:

- Apple App Store server API credentials/signing trust config
- Google Play developer service account keys
- Paddle webhook secret/API key
- Toss webhook secret/API key

## Notes

- Mobile policy is supported by design: no external checkout requirement on iOS/Android clients.
- Current provider signature checks are scaffolded and intentionally strict by default. Wire real verification before production launch.
- Event projector is deterministic and idempotent; stale revisions do not overwrite newer entitlement snapshots.
