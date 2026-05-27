# Developer TODO

Short, practical launch list for the current beta push.

## 0. Config / Secrets Map

Use this section as the top-level reference for where config should live.

### Safe in Flutter app build

These are okay to ship in the client app, either via `--dart-define` or hardcoded defaults:

- `POSTHOG_API_KEY`
- `POSTHOG_HOST`
- `SENTRY_DSN`
- `APP_ENV`
- `LLM_PROXY_API_BASE_URL`
- `APP_API_BASE_URL`
- feature flags like `SUBSCRIPTION_ENFORCE`, `SUBSCRIPTION_SHADOW_MODE`, `IAP_ENABLE_PURCHASES`

### Server-only secrets

These should live in backend-only AWS env vars, SAM parameters, or SSM
Parameter Store, not in Dart:

- `OPENAI_API_KEY`
- provider secret referenced by `LLM_API_KEY_PARAMETER_NAME` / `OpenAiApiKeyParameterName`
- Apple shared secret
- Apple root certificate bundle
- Google Play service account JSON
- Paddle webhook secret
- Toss webhook secret

### Rule of thumb

- If the Flutter app needs the value directly at runtime, assume users can inspect it.
- Real secrets belong on the backend only.
- Client SDK config like PostHog and Sentry identifiers are fine in the app.

### Detailed setup docs

- Remote-operable app surfaces and rollback/testing SOPs:
  - [REMOTE_OPERATIONS.md](REMOTE_OPERATIONS.md)
- LLM proxy secrets and deploy inputs:
  - [backend/llm_proxy/README.md](../backend/llm_proxy/README.md)
  - [BETA_AWS_OPENAI_SETUP_CHECKLIST.md](BETA_AWS_OPENAI_SETUP_CHECKLIST.md)
- App API billing/setup secrets and external setup:
  - [backend/app_api/SETUP_CHECKLIST.md](../backend/app_api/SETUP_CHECKLIST.md)
  - [backend/app_api/FIRST_DEPLOY_FROM_AWS_CONSOLE.md](../backend/app_api/FIRST_DEPLOY_FROM_AWS_CONSOLE.md)
- Analytics and crash config:
  - [ANALYTICS.md](ANALYTICS.md)
- DevOps / deployment follow-ups:
  - [DEVOPS_TODO.md](DEVOPS_TODO.md)

## 1. Infra / Auth / Security

- Deploy AWS LLM proxy and make it the real app path.
- Configure Cognito hosted UI, callbacks, logout URLs, and providers.
- Store OpenAI key only in AWS secrets/env, not in the app.
- Revoke any old client-exposed OpenAI key after proxy verification.
- LLM proxy reminder:
  - backend now has a provider adapter boundary, so Flutter does not need changes when switching backend LLMs
  - supported backend provider values are `openai`, `gemini`, and `claude`
  - switch providers later with backend envs: `LLM_PROVIDER` + `LLM_MODEL`
  - current setup only has an OpenAI API key; if Gemini or Claude are tested later, add their key to SSM Parameter Store at that time
  - app-facing backend response is still normalized to the current OpenAI Responses-style shape so existing Flutter parsing stays intact
  - Flutter direct debug fallback is still OpenAI-only; production path should stay backend-only
  - do one real smoke test against live provider credentials after any provider switch
  - relevant backend files:
    - [api_responses.py](../backend/llm_proxy/src/handlers/api_responses.py)
    - [llm_provider.py](../backend/llm_proxy/src/common/llm_provider.py)
    - [llm_contract.py](../backend/llm_proxy/src/common/llm_contract.py)
    - [template.yaml](../backend/llm_proxy/template.yaml)
    - [README.md](../backend/llm_proxy/README.md)
- Run real-device auth QA using:
  - [BETA_EXTERNAL_SETUP_CHECKLIST.md](BETA_EXTERNAL_SETUP_CHECKLIST.md)
  - [BETA_AUTH_QA_CHECKLIST.md](BETA_AUTH_QA_CHECKLIST.md)
  - [BETA_AWS_OPENAI_SETUP_CHECKLIST.md](BETA_AWS_OPENAI_SETUP_CHECKLIST.md)

## 2. Subscriptions / Payments

- Keep mobile payments off during beta:
  - `IAP_ENABLE_PURCHASES=false`
  - `SUBSCRIPTION_ENFORCE=false` or `SUBSCRIPTION_SHADOW_MODE=true`
- Keep IAP initialization lazy:
  - do not initialize Play Billing / StoreKit during app startup
  - do not trigger `iap.initialize()` from widget `build()` methods
  - especially avoid eager init inside pages that are children of an `IndexedStack`, because hidden tabs still build
  - initialize IAP only when the user opens real subscription UI or taps a purchase / restore / refresh-store action
- RevenueCat is no longer required for Mixroom's mobile subscription flow if the in-house AWS app API backend is deployed and the Apple/Google setup is completed correctly.
- AWS is required for the in-house app API backend.
- Learn only the minimum AWS pieces:
  - AWS account
  - AWS Console access
  - AWS CloudShell
  - one guided deploy of [backend/app_api](../backend/app_api)
- Treat DynamoDB as an internal AWS database created by the deploy, not a separate product to learn deeply right now.
- When ready for paid launch, deploy the app API backend in [backend/app_api](../backend/app_api).
- Browser-first deploy guide: [FIRST_DEPLOY_FROM_AWS_CONSOLE.md](../backend/app_api/FIRST_DEPLOY_FROM_AWS_CONSOLE.md)
- Seed the minimal catalog mapping rows:
  - `apple:YOUR_PRODUCT_ID -> pro`
  - `google:YOUR_PRODUCT_ID -> pro`
- Use the helper script instead of hand-writing DynamoDB rows:
  - [seed_catalog_mappings.py](../backend/app_api/scripts/seed_catalog_mappings.py)
- In App Store Connect:
  - create the subscription product IDs used by the app
  - enable App Store Server Notifications V2
  - complete Apple banking + tax forms so Apple can pay out subscription revenue
  - store Apple shared secret in SSM `SecureString`; store Apple root certs as non-secret config such as a plain SSM `String`
- In Google Play Console / Google Cloud:
  - create the subscription + base plan
  - enable Android Publisher API
  - create a service account with Play app access
  - finish the Google payments profile, payouts, and tax setup
  - configure RTDN Pub/Sub push to the backend webhook
- Remember where money actually arrives for mobile subscriptions:
  - iOS payouts come from Apple, configured in App Store Connect
  - Android payouts come from Google, configured in Play Console payments profile
  - AWS does not receive or move subscription money
- Run sandbox purchase QA before enabling real payments:
  - purchase
  - restore
  - renewal
  - cancel at period end
  - expiration
  - refund / revoke
- Specifically verify edge cases that usually bite subscription launches:
  - purchase succeeds while backend is temporarily unreachable, then app restart retries verification automatically
  - duplicate webhook delivery does not duplicate access or corrupt state
  - out-of-order events do not downgrade a still-active subscription
  - same user has more than one subscription record and the highest active entitlement still wins
  - purchase restore on a different device re-links to the same Mixroom account
  - purchase tied to a different Mixroom account is rejected cleanly
  - delete-account is blocked while a paid subscription is still active
- Before turning payments on, add final subscription disclosure copy in the app:
  - clear price / billing period
  - auto-renew / cancel terms
  - terms + privacy links near purchase UI
- Do not add web checkout or external purchase CTA on mobile without a separate Apple / Google policy review.
- Web billing is later, not needed for beta or first mobile paid launch.
- If web billing is added later with Paddle:
  - complete Paddle business verification
  - connect payout bank account
  - finish tax/business profile
  - store Paddle webhook secret in AWS
  - test checkout, renewals, refunds, and payout reports
- If KR web billing is added later with Toss:
  - complete Toss merchant onboarding
  - connect settlement bank account
  - finish business/tax documents
  - store Toss webhook secret in AWS
  - test payment success, refund, cancel, and settlement flows
- Start subscription analytics simple:
  - use App Store Connect and Play Console dashboards first
  - use AWS billing events / entitlements as your source of truth inside Mixroom
  - review weekly: active paid users, new purchases, restores, cancels, refunds, expirations
- For finance/accounting, always use Apple/Google/Paddle/Toss payout reports as the source of truth, not analytics dashboards.
- Use the helper report later for rough KPI snapshots:
  - [subscription_kpi_report.py](../backend/app_api/scripts/subscription_kpi_report.py)
- Do not build a full BI/data warehouse stack yet unless revenue justifies it.
- Full external setup checklist: [backend/app_api/SETUP_CHECKLIST.md](../backend/app_api/SETUP_CHECKLIST.md)

## 2A. App User Bootstrap / Platform Prep

- Deploy the updated app API stack so `mixroom-users-*` and `GET /v1/users/me` exist.
- Keep signup frictionless: no extra onboarding step is required now because the app-user row is lazily created after sign-in from Cognito claims.
- `PATCH /v1/users/me` and case-insensitive handle claiming are now implemented in the backend.
- `DELETE /v1/users/me` is now implemented for Mixroom-side account cleanup, but active paid subscriptions must be cancelled first.
- Current default handle rules:
  - 1-30 chars
  - lowercase letters, numbers, underscores, hyphens
  - cannot start/end with separator
  - reserved system/admin words are blocked
- Before public profiles launch, review:
  - reserved handle list
  - profile visibility and moderation states
- Short pre-platform account checklist:
  - treat Cognito `sub` as the canonical internal user id for all future platform tables; never key platform data off email, handle, or provider username
  - keep auth identity separate from Mixroom profile data; future artist/org/team roles should live in Mixroom DB, not Cognito custom attributes
  - lock handle policy before platform work: rename rules, cooldown/history, reserved handles, and whether deleted handles can ever be reused
  - add explicit account lifecycle states separate from billing state, e.g. `active`, `suspended`, `deleted`, `pending_review`
  - store terms/privacy acceptance version + timestamp per account before enabling public uploads or platform-specific features
  - keep profile/account audit history for handle changes, moderation actions, and delete requests
- Current auth/password behavior:
  - email accounts can sign in with email/password and change password from Account
  - social accounts can sign in only with their social provider right now
  - if social accounts should also support email/password later, implement an explicit Cognito account-linking strategy first; do not bolt on a naive set-password flow
  - same email across social login and email/password can create separate identities unless account linking is implemented deliberately
- Keep the delete-account copy explicit:
  - deleting a Mixroom account does not cancel App Store / Google Play billing
  - users must cancel active subscriptions first
- Later, define retention/anonymization policy for historical billing/audit events when accounts are deleted.
- When profile photos or cover art are added, store media in object storage + CDN, not in the user table.
- Before uploads/streaming/comments launch, separately design the content storage layer for tracks, comments, likes, follows, and moderation events.

## 3. AI Beta Readiness

- Keep beta AI focused on corrective mixing, DAW actions, and helpful explanations.
- Replace bootstrap ONNX models with real producer-trained corrective models.
- Collect producer sessions for:
  - muddy
  - harsh
  - boomy
  - vocals too quiet
  - low-end conflict
  - clarity / cleanup / balance
- Run the full training pipeline in [tools/ai_mixing](../tools/ai_mixing).
- Validate the trained ONNX models on real projects before enabling the feature broadly.
- Keep learned-model fallback behavior stable if the model is unavailable or weak.
- Do not expand the beta mixing lane beyond the current core actions.
- Leave stylistic mixing training for after beta.

## 4. AI QA

- Test authenticated chat through AWS proxy only.
- Test informational prompts, DAW assistant prompts, and corrective mix prompts.
- Test no-audio, ambiguous, expired-session, and network-failure cases.
- Check latency, repeated-prompt consistency, and no-op behavior.
- Prompt-cycle observability is now live; use admin/PostHog to confirm:
  - runtime fingerprint
  - tool path
  - learned-model usage / fallback
  - end-to-end latency breakdown

## 5. Playback / Device QA

- Fix or confirm Android + Bluetooth + AirPods behavior on real hardware.
- Run export regression tests, including stretched clips and cross-platform open/share.
- Test `.mixroom` open/import from outside the app.
- Test MIDI controller / SFZ / piano roll flow on real devices.
- *Before or shortly after beta, consolidate sampled-instrument rendering to one authoritative engine path:*
  - current state is `Dart SFZ render first`, with `JUCE/native` fallback on Android
  - this is acceptable for beta, but not ideal long-term DAW architecture
  - target state should be `JUCE/native` as the single source of truth for sampled-instrument render/playback on both iOS and Android, then remove the duplicated Dart SFZ renderer after parity is verified
- Do one focused performance pass on playback, timeline, and EQ hotspots.

## 6. Beta Freeze

- Do not add major new product features before beta.
- Only do bug fixes, performance work, auth/backend setup, and AI readiness work.
- Keep payments, stylistic-mixing expansion, cloud storage, and platform extras for later.

## 7. Analytics / Monitoring

- PostHog and Sentry are already wired for the current production path.
- Keep app/build/backend env values aligned:
  - Flutter `APP_ENV`
  - backend `StageName`
- For release builds, keep Sentry symbol/upload steps healthy so stack traces stay readable.
- Keep admin/PostHog observability working for:
  - prompt timing
  - prompt failures
  - tool usage
  - remote magnitude model usage/update events
  - remote welcome / announcement events
- Deploy the subscriptions stack with PostHog and Sentry envs enabled.
- In PostHog, verify these events are arriving from real test sessions:
  - `app_opened`
  - `user_logged_in`
  - `project_created`
  - `export_started`
  - `ai_prompt_submitted`
  - `ai_response_completed`
  - `ai_usage_limit_hit`
  - `subscription_started`
- In PostHog, create the first dashboards/funnels:
  - DAU by `app_opened`
  - activation funnel: `user_signed_up` -> `project_created` -> `subscription_started`
  - AI usage by `ai_feature`
  - AI limit pressure by `ai_usage_limit_hit`
  - export completion rate from `export_started` -> `export_completed`
- In PostHog, inspect person properties and ensure `subscription_tier`, `platform`, `app_version`, and `environment` look correct.
- In Sentry, add at least one alert for new production issues and one alert for backend error spikes.
- In CloudWatch, confirm the backend logs are showing JSON objects with:
  - `request_id`
  - `user_id`
  - `endpoint`
  - `project_id`
  - `latency_ms`
  - `error`
- Run one end-to-end QA pass for analytics:
  - app launch
  - login
  - create project
  - upload track
  - play track
  - open AI assistant
  - send AI request
  - export project
  - start subscription flow
- Confirm the privacy toggle in [legal_privacy_center.dart](../lib/screens/legal_privacy_center.dart) actually stops both analytics and Sentry delivery.
- Review [ANALYTICS.md](ANALYTICS.md) before adding any new events.
- Keep event growth controlled. Add a new event only when it answers a real product, monetization, or operational question.
- Later improvement:
  - move `export_completed` to backend analytics if exports become server-side or cloud-processed
