# Mixroom App API (AWS)

This package is the main authenticated backend for Mixroom.

Today it owns:

- app-user bootstrap and profile endpoints
- native social sign-in completion against Cognito
- entitlement and billing APIs
- billing catalog and collaboration APIs
- admin overview APIs

It still contains the in-house subscription core that normalizes Apple IAP, Google IAP, Paddle, and Toss into one canonical entitlement record per Cognito user.

## What is implemented

- Canonical domain model for plans/providers/statuses.
- Client APIs:
- `GET /v1/entitlements/me`
- `GET /v1/billing/catalog`
- `GET /v1/users/me`
- `PATCH /v1/users/me`
- `DELETE /v1/users/me`
- `GET /v1/organizations/me`
- `GET /v1/workspaces/me`
- `GET /v1/cloud-projects/me`
- `GET /v1/cloud-projects/{project_id}`
- `PUT /v1/cloud-projects/{project_id}`
- `POST /v1/billing/web/checkout-session`
  - `POST /v1/billing/mobile/apple/verify`
  - `POST /v1/billing/mobile/google/verify`
  - `POST /v1/billing/restore`
  - `GET /v1/billing/portal-url`
- Admin APIs:
  - `GET|PUT /v1/internal/admin/settings/billing-catalog`
  - `GET|POST /v1/internal/admin/billing/organizations`
  - `GET|POST /v1/internal/admin/billing/memberships`
  - `GET|POST /v1/internal/admin/billing/workspaces`
  - `GET|POST /v1/internal/admin/billing/cloud-projects`
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
cd backend/app_api
sam build
sam deploy --guided
```

This deploy creates the DynamoDB tables for you. You do not create them by hand.

The preferred Flutter define for this backend is `APP_API_BASE_URL`.
`SUBSCRIPTION_API_BASE_URL` is still accepted as a legacy fallback so older local scripts do not break.

If you prefer the AWS website over a local terminal, use:

- [FIRST_DEPLOY_FROM_AWS_CONSOLE.md](FIRST_DEPLOY_FROM_AWS_CONSOLE.md)

## Helper scripts

- Print or apply the minimal product mapping rows:

```bash
python3 scripts/seed_catalog_mappings.py
python3 scripts/seed_catalog_mappings.py --apply --stage staging
```

- Print a rough subscription KPI snapshot after the backend is live:

```bash
python3 scripts/subscription_kpi_report.py --stage staging
```

- Run a live auth smoke test against deployed `app_api` and optionally `llm_proxy`:

```bash
APP_API_BASE_URL=https://YOUR_APP_API \
LLM_PROXY_API_BASE_URL=https://YOUR_LLM_PROXY \
MIXROOM_TEST_EMAIL=test-user@example.com \
MIXROOM_TEST_PASSWORD=... \
python3 scripts/live_auth_smoke.py
```

This checks sign-in, `GET /v1/users/me`, refresh-token rotation, stale-token rejection after refresh, and sign-out invalidation. If `LLM_PROXY_API_BASE_URL` is set, it also checks `GET /v1/llm/limits` with the same stale-token and sign-out expectations.

## Required environment and secrets

Environment variables (set by template and per-stage overrides):

- `BILLING_EVENTS_TABLE`
- `SUBSCRIPTIONS_TABLE`
- `ENTITLEMENTS_TABLE`
- `USERS_TABLE`
- `USERNAME_CLAIMS_TABLE`
- `CATALOG_MAPPINGS_TABLE`
- `COLLABORATION_TABLE`
- `CUSTOMER_LINKS_TABLE`
- `PURCHASE_TOKENS_TABLE`
- `RECONCILIATION_JOBS_TABLE`
- `PROJECTION_QUEUE_URL`
- `CLOUD_PROJECT_DOCUMENTS_BUCKET`
- `AWS_REGION`
- `ALLOW_STUDIO_TIER`

Provider secrets should be stored in Secrets Manager and read by handlers:

- Apple App Store signed-data trust config / receipt shared secret
- Google Play developer service account keys
- Paddle webhook secret/API key
- Toss webhook secret/API key

## Notes

- RevenueCat is optional now. This backend replaces the core Apple/Google subscription verification, webhook, entitlement, and restore flow as long as AWS and the store-side setup are completed correctly.
- `GET /v1/users/me` auto-creates or refreshes the app-level user row from verified Cognito claims.
- `PATCH /v1/users/me` updates app-profile fields like username and bio.
- `DELETE /v1/users/me` deletes Mixroom-side user/profile/link data, but intentionally refuses if the user still has an active paid subscription.
- `GET /v1/billing/catalog` is now the source of truth for visible plans, products, offers, and support URLs. The hardcoded `free/pro/studio` tier is preserved only as the compatibility rail for the existing projector.
- `GET /v1/organizations/me`, `GET /v1/workspaces/me`, and `GET /v1/cloud-projects/me` expose the shared-workspace and cloud-project layer used by Studio, Enterprise, and Education plans.
- `GET|PUT /v1/cloud-projects/{project_id}` adds a minimal authenticated cloud-project document rail with optimistic locking via `expected_revision`.
- The admin billing endpoints are the intended control plane for plan configuration, manual contract activation, org seats, workspaces, and cloud-project metadata.
- Username uniqueness is enforced server-side with a dedicated case-insensitive username-claim table.
- Mobile policy is supported by design: no external checkout requirement on iOS/Android clients.
- Apple purchases are verified through signed transaction JWS or legacy receipt fallback.
- Google purchases are verified against the Play Developer API.
- Apple server notifications and Google RTDN are intended to be the canonical renewal/refund/revoke sources once configured.
- Team-plan cloud projects are intentionally split from telemetry. Use `COLLABORATION_TABLE` for authoritative org/workspace/project metadata and `CLOUD_PROJECT_DOCUMENTS_BUCKET` for versioned project document blobs.
- The backend now verifies Cognito JWTs itself when API Gateway authorizers are not present.
- Event projector is deterministic and idempotent; stale revisions do not overwrite newer entitlement snapshots.

## Reporting Approach

- For now, Mixroom will use the native dashboards manually instead of a paid analytics aggregator.
- Subscription and revenue review should come from:
  - App Store Connect
  - Google Play Console
  - Paddle dashboard, if web billing is added later
  - Toss dashboard, if KR web billing is added later
- Mixroom's own AWS subscription data is useful for product-state reporting such as active entitlements, restores, cancels, refunds, and churn signals.
- For finance/accounting, always treat Apple/Google/Paddle/Toss payout reports as the source of truth, not the analytics dashboard.

## Production setup

See [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) for the required AWS, App Store Connect, and Google Play Console configuration.
