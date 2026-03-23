# Mixroom Analytics

This repo now has a minimal analytics foundation built around PostHog for product analytics and Sentry for crash monitoring.

The implementation is intentionally simple:

- Flutter sends product and screen events through one centralized service.
- Backend sends authoritative events for AI requests and subscription starts.
- Sentry handles crashes and unhandled exceptions separately from analytics.
- Analytics failures are silent and must not break app flows.

## Architecture

Flutter entry points:

- [analytics_service.dart](../lib/core/analytics/analytics_service.dart)
- [analytics_events.dart](../lib/core/analytics/analytics_events.dart)
- [crash_reporting_service.dart](../lib/core/crash_reporting/crash_reporting_service.dart)

Backend entry points:

- [api_responses.py](../backend/llm_proxy/src/handlers/api_responses.py)
- [api_billing.py](../backend/app_api/src/handlers/api_billing.py)

Rules:

- Do not call PostHog directly from random widgets.
- Add new product events in `AnalyticsEvents` and send them through `AnalyticsService`.
- Do not send raw AI prompts, emails beyond identify usage, or other sensitive content in event payloads.
- Use backend analytics for authoritative actions when the backend is the source of truth.

## Global Event Properties

These are attached automatically when available:

- `user_id`
- `distinct_id`
- `device_id`
- `session_id`
- `app_version`
- `platform`
- `environment`
- `timestamp`
- `locale`
- `subscription_tier`

Optional event-specific properties include:

- `project_id`
- `track_id`
- `track_count`
- `file_size`
- `file_type`
- `upload_method`
- `export_type`
- `duration_ms`
- `ai_feature`
- `model_name`
- `tokens_prompt`
- `tokens_completion`
- `tokens_total`
- `success`

## Event Taxonomy

### Lifecycle

- `app_opened`
- `session_started`
- `session_ended`

### Auth

- `user_signed_up`
- `user_logged_in`
- `user_logged_out`

### Product

- `project_created`
- `first_project_created`
- `project_opened`
- `upload_failed`

### Export

- `export_started`
- `export_completed`
- `export_failed`

### AI

- `ai_feature_viewed`
- `ai_prompt_submitted`
- `ai_response_completed`
- `ai_response_failed`
- `ai_tool_called`
- `ai_usage_limit_hit`

### Monetization

- `subscription_started`
- `purchase_failed`

## Event Sources

Flutter-owned events:

- lifecycle events
- auth events
- project creation/opening
- export started/completed/failed
- screen views
- `ai_feature_viewed`
- `ai_tool_called`
- `purchase_failed`

Backend authoritative events:

- `ai_prompt_submitted`
- `ai_response_completed`
- `ai_response_failed`
- `ai_usage_limit_hit`
- `subscription_started`

Current gap:

- `export_completed` is currently client-side because exports are local in the Flutter app. If export processing moves to the backend later, move the authoritative completion event there too.

## Screen Tracking

Major screens tracked today:

- `home`
- `projects_list`
- `project_editor`
- `upload`
- `export`
- `ai_assistant`
- `paywall`
- `settings`

Screen tracking is deduplicated in `AnalyticsService.trackScreen()` so rebuilds do not create duplicate events.

## AI Usage Tracking

The LLM proxy tracks:

- `ai_prompt_submitted`
- `ai_response_completed`
- `ai_response_failed`
- `ai_usage_limit_hit`

The proxy also records per-user usage metrics in DynamoDB:

- `ai_requests_today`
- `ai_tokens_prompt`
- `ai_tokens_completion`
- `ai_tokens_total`

Implementation:

- [usage_repository.py](../backend/llm_proxy/src/common/usage_repository.py)
- [analytics.py](../backend/llm_proxy/src/common/analytics.py)

Token counts come from the upstream model response usage fields after normalization in the LLM provider layer.

## Crash Monitoring

Flutter:

- unhandled Flutter framework errors are sent to Sentry
- uncaught platform errors are sent to Sentry
- Sentry user context is set after login and cleared on logout

Backend:

- API handler exceptions are captured in Sentry for the LLM proxy and app API service

Implementation:

- [main.dart](../lib/main.dart)
- [crash_reporting_service.dart](../lib/core/crash_reporting/crash_reporting_service.dart)
- [monitoring.py](../backend/llm_proxy/src/common/monitoring.py)
- [monitoring.py](../backend/app_api/src/common/monitoring.py)

## Logging

Backend handlers now emit structured JSON logs suitable for CloudWatch with:

- `request_id`
- `user_id`
- `endpoint`
- `project_id`
- `latency_ms`
- `error`

Implementation:

- [logging_utils.py](../backend/llm_proxy/src/common/logging_utils.py)
- [logging_utils.py](../backend/app_api/src/common/logging_utils.py)

## Configuration

Flutter compile-time defines:

- `POSTHOG_API_KEY`
- `POSTHOG_HOST`
- `SENTRY_DSN`
- `APP_ENV`

Backend environment values:

- `POSTHOG_API_KEY`
- `POSTHOG_HOST`
- `SENTRY_DSN`
- `ENVIRONMENT`

Additional backend AI usage env:

- `AI_USAGE_METRICS_TABLE`

The Flutter privacy toggle controls both analytics and crash diagnostics. When disabled:

- PostHog events stop sending
- Sentry event delivery is blocked
- backend event sending is disabled for requests initiated by that client
- backend AI usage counters may still update for operational metering and limits
