# Mixroom Technical Index

Use this file as the concise source of truth for what Mixroom runs, where it
lives, and which deeper docs matter.

If a new service, vendor, or deploy surface is introduced, update this page
first and then add the deeper doc if needed.

## Current Stack

### Product surfaces

- Flutter app for iOS, Android, macOS, and Windows
- `backend/app_api`: main authenticated backend for users, profiles,
  entitlements, billing, admin APIs, and webhooks
- `backend/llm_proxy`: authenticated AI proxy that owns the server-side prompt,
  model, and tool contract
- `admin_site`: employee-facing admin site hosted separately from the app

### Core technical stack

- Flutter + Dart for the client app
- JUCE audio engine for native audio processing
- FFmpeg Kit for media processing
- ONNX Runtime for local model inference
- AWS SAM / CloudFormation for backend and infra deploys

## Services We Use

### AWS

- Cognito: admin employee auth and remaining legacy/compatibility paths, not
  the primary app auth system
- API Gateway: public app and AI APIs
- Lambda: serverless backend handlers
- DynamoDB: users, entitlements, billing, admin, and AI usage state
- SQS: billing projection / async processing
- EventBridge: scheduled reconciliation jobs
- SSM Parameter Store: provider keys and webhook secrets
- CloudWatch: logs, metrics, alarms
- SNS: alarm fan-out
- WAF: optional shared protection for public APIs
- S3 + CloudFront: admin site hosting and remote manifests/assets
- Route 53: DNS for hosted surfaces when custom domains are used

### Third-party product services

- OpenAI / Anthropic / Google: pluggable cloud AI providers for the LLM proxy
- PostHog: product analytics
- Sentry: crash reporting and backend error monitoring
- Postmark: transactional auth email delivery
- Apple App Store / App Store Connect: iOS distribution, Sign in with Apple,
  in-app purchases
- Google Play / Play Developer API / Google Sign-In: Android distribution,
  in-app purchases, social sign-in
- Kakao: social sign-in
- YouTube / Google OAuth: user-initiated upload flows

### Supported or conditional services

- Paddle: supported in the billing backend for web checkout/webhooks if enabled
- Toss: supported in the billing backend for KR web billing if enabled
- Slack: alert delivery target for production alarms

## Remote / Runtime-Controlled Surfaces

- AI runtime overrides and free prompt limits via admin APIs
- Remote welcome onboarding manifest
- Remote announcement manifest
- Remote magnitude-model manifests and model bundles

See [REMOTE_OPERATIONS.md](REMOTE_OPERATIONS.md).

## Where To Look First

### Operations

- [REMOTE_OPERATIONS.md](REMOTE_OPERATIONS.md): runtime-safe changes without a
  new app release
- [ANALYTICS.md](ANALYTICS.md): analytics, crash reporting, and logging
- [DESKTOP_PLUGIN_HOSTING.md](DESKTOP_PLUGIN_HOSTING.md): desktop plugin-host
  signing/runtime notes

### Backend / Infra

- [backend/app_api/README.md](../backend/app_api/README.md): app API scope and
  deploy model
- [backend/llm_proxy/README.md](../backend/llm_proxy/README.md): AI proxy scope
  and deploy model
- [admin_site/README.md](../admin_site/README.md): admin site architecture and
  deploy flow
- [DEVOPS_TODO.md](DEVOPS_TODO.md): small infra backlog

### Setup / QA

- [BETA_EXTERNAL_SETUP_CHECKLIST.md](BETA_EXTERNAL_SETUP_CHECKLIST.md): outside
  consoles/services required for beta
- [BETA_AWS_OPENAI_SETUP_CHECKLIST.md](BETA_AWS_OPENAI_SETUP_CHECKLIST.md):
  beta AWS + AI setup
- [BETA_AUTH_QA_CHECKLIST.md](BETA_AUTH_QA_CHECKLIST.md): auth QA matrix
- [INTEGRATION_TESTS.md](INTEGRATION_TESTS.md): integration test notes

### Legal / Vendor Disclosure

- [SUBPROCESSORS.md](SUBPROCESSORS.md): privacy-facing vendor list
- [PRIVACY_POLICY.md](PRIVACY_POLICY.md)
- [TERMS_OF_SERVICE.md](TERMS_OF_SERVICE.md)
- [EULA.md](EULA.md)
- [DELETE_ACCOUNT.md](DELETE_ACCOUNT.md)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

### Product / Architecture

- [AI_MIXING_OVERVIEW.md](AI_MIXING_OVERVIEW.md)
- [PLUGIN_AUTOMATION_BLUEPRINT.md](PLUGIN_AUTOMATION_BLUEPRINT.md)
- [BETA_FEATURE_AUDIT.md](BETA_FEATURE_AUDIT.md)

### Backlogs

- [DEVELOPER_TODO.md](DEVELOPER_TODO.md)
- [DEVOPS_TODO.md](DEVOPS_TODO.md)
- [PLATFORM_TODO.md](PLATFORM_TODO.md)
