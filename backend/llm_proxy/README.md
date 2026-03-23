# Mixroom LLM Proxy (AWS)

This package is the minimal beta-safe backend for Mixroom chat. Its job is to:

- keep the provider API key off the client,
- require authenticated Mixroom users,
- own the production prompt/tool/model contract server-side.

## Current scope

- `POST /v1/llm/responses`
- Accepts either:
  - a Mixroom app payload (`conversation`, `user_text`, `project_snapshot`, etc.), or
  - a sanitized OpenAI-compatible payload during migration
- Validates the caller through API Gateway JWT auth backed by Cognito
- Builds a provider-neutral internal LLM request in Lambda
- Pins prompt/tool schema on the server path
- Forwards the request through a pluggable provider adapter using a server-side secret
- Returns an OpenAI Responses-compatible JSON body to the app

This is the beta target architecture. The app should send context only; Lambda owns the server prompt, tools, and default model.

## AWS services

For beta, you do not need EC2.

Use:

- API Gateway HTTP API
- AWS Lambda
- Amazon Cognito User Pool
- AWS Secrets Manager
- CloudWatch Logs

Optional later additions:

- AWS WAF for stricter abuse filtering
- Route 53 / CloudFront custom domain in front of the API

## Deploy (SAM)

```bash
cd backend/llm_proxy
sam build
sam deploy --guided
```

## Required parameters

- `CognitoUserPoolId`
- `CognitoAppClientId`
- `LlmProvider`
  Recommended values: `openai`, `gemini`, `claude`
- `OpenAiApiKeySecretArn` (legacy name, still used by the SAM template)
- `EntitlementsTableName`

## Environment

- `LLM_PROVIDER`
- `LLM_API_KEY_SECRET_ARN`
- `LLM_MODEL`
- `LLM_TIMEOUT_SECONDS`
- `LLM_SECRET_CACHE_TTL_SECONDS`
- `ANTHROPIC_VERSION`
- `OPENAI_API_KEY_SECRET_ARN`
- `OPENAI_MODEL`
- `OPENAI_TIMEOUT_SECONDS`
- `OPENAI_SECRET_CACHE_TTL_SECONDS`
- `MAX_REQUEST_BYTES`
- `ALLOW_CLIENT_MODEL_OVERRIDE`
- `AI_USAGE_STATE_TABLE`
- `AI_USAGE_EVENTS_TABLE`
- `ENTITLEMENTS_TABLE`
- `LLM_MAX_OUTPUT_TOKENS`
- `LLM_UPSTREAM_NETWORK_RETRY_ATTEMPTS`

## Secrets

Store the active provider API key in AWS Secrets Manager.

Accepted secret formats:

1. Plain string secret:
```text
sk-...
```

2. JSON secret:
```json
{
  "LLM_API_KEY": "..."
}
```

Provider-specific JSON keys such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, or other `*_API_KEY` names are also accepted.

## Rotation

No special provider-side configuration is required for key rotation.

Recommended flow:

1. Create a new API key for the active provider.
2. Update the AWS Secrets Manager secret value.
3. Wait for the Lambda secret cache TTL to expire, or redeploy/invalidate warm containers.
4. Verify the proxy works with the new key.
5. Revoke the old key.

By default, the Lambda refreshes the secret every 5 minutes via `LLM_SECRET_CACHE_TTL_SECONDS=300`.

## App configuration

Run the app with:

```bash
flutter run \
  --dart-define=LLM_PROXY_API_BASE_URL=https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/YOUR_STAGE
```

To verify deployed auth behavior with a real native-auth account, run:

```bash
APP_API_BASE_URL=https://YOUR_APP_API \
LLM_PROXY_API_BASE_URL=https://YOUR_LLM_PROXY \
MIXROOM_TEST_EMAIL=test-user@example.com \
MIXROOM_TEST_PASSWORD=... \
python3 ../app_api/scripts/live_auth_smoke.py
```

That live smoke checks that refreshed sessions invalidate stale tokens and that `GET /v1/llm/limits` rejects stale or signed-out tokens while accepting the refreshed token.

Backend provider examples:

- `LLM_PROVIDER=openai` with `LLM_MODEL=gpt-4.1-mini`
- `LLM_PROVIDER=gemini` with `LLM_MODEL=gemini-2.5-flash`
- `LLM_PROVIDER=claude` with `LLM_MODEL=claude-sonnet-4-5`

Optional transitional fallback for local debug only:

```bash
flutter run \
  --dart-define=OPENAI_API_KEY=sk-... \
  --dart-define=OPENAI_MODEL=gpt-4.1-mini
```

Direct OpenAI fallback is disabled in release unless explicitly enabled with:

```bash
--dart-define=LLM_ALLOW_DIRECT_OPENAI_IN_RELEASE=true
```

## Notes

- API Gateway stage throttling is configured in the SAM template via
  `ApiThrottleBurstLimit` and `ApiThrottleRateLimit`.
- Optionally attach a regional WAF WebACL by passing `WebAclArn` at deploy time.
- Request-body limits are enforced in the Lambda handler.
- The proxy owns the server-side prompt/tool contract for structured Mixroom requests.
- The proxy normalizes structured requests before handing them to a provider adapter.
- The proxy allowlists/sanitizes raw OpenAI-compatible request fields only for transitional fallback.
- The app-facing response stays OpenAI Responses-compatible so provider swaps do not require Flutter changes.
- CloudWatch logging should be kept metadata-only; do not log full prompts or snapshots in production.
- Keeping this serverless code in the same monorepo is fine; deployment target and secret boundary matter more than repository layout.

## AI credits and rate limits

The LLM proxy now enforces AI usage server-side before the upstream provider call.

Single source of truth:

- `src/config/ai_limits.ts`

The file defines:

- per-tier limits (`daily_credits`, `monthly_tokens`)
- per-feature base costs
- the token-to-credit ratio

For the current app shape, all chatbar LLM requests should be billed as `ai_chat`.
Specific outcomes such as `mix_model_request`, `daw_assistant_actions`, or
`informational_response` are logged separately as resolved tools for analytics/debugging,
not treated as different preflight billable features.

### How charging works

1. The proxy resolves the user tier from the subscriptions entitlement table.
2. It normalizes the feature name and loads the limits from `src/config/ai_limits.ts`.
3. It applies a server-side `max_output_tokens` cap.
4. It reserves quota in DynamoDB using a conditional update before calling the provider.
5. When the provider returns, it computes the final credit charge:

```text
base_feature_cost + ceil(total_tokens / tokens_per_credit)
```

6. It adjusts the reserved counters to the final token/credit totals.
7. If the provider call fails, the reservation is released and credits are not deducted.

### Usage state storage

Because the current backend stack is AWS Lambda + DynamoDB, there is no SQL `users` table or migration layer here.

Per-user usage state is stored in the `AI_USAGE_STATE_TABLE` item keyed by `user_id` with these fields:

- `ai_credits_used_today`
- `ai_tokens_used_month`
- `ai_last_reset`
- `ai_tokens_month_reset`
- `subscription_tier`

Daily and monthly resets are applied lazily by the proxy when a user makes a request.

### Historical usage ledger

Every request attempt is logged to `AI_USAGE_EVENTS_TABLE`.

Each event stores:

- `id`
- `user_id`
- `project_id` (optional)
- `feature`
- `resolved_tool` (optional)
- `model`
- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `credits_charged`
- `status`
- `error_code` (optional)
- `created_at`

This table is for analytics, support debugging, and reconciliation. It is not used to enforce limits.

### Adding or changing feature costs

Update `src/config/ai_limits.ts`.

If the client sends a new `ai_feature` name, also add a canonical alias in `src/common/ai_limits.py` if you need backward-compatible naming (for example `assistant_chat` -> `ai_chat`).
