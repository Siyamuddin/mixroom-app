import os

POSTHOG_API_KEY = os.environ.get("POSTHOG_API_KEY", "").strip()
POSTHOG_HOST = os.environ.get("POSTHOG_HOST", "").strip()
SENTRY_DSN = os.environ.get("SENTRY_DSN", "").strip()
ENVIRONMENT = os.environ.get("ENVIRONMENT", "").strip() or "dev"
APP_AUTH_SECRET_ARN = os.environ.get("APP_AUTH_SECRET_ARN", "").strip()
APP_AUTH_ISSUER = os.environ.get("APP_AUTH_ISSUER", "").strip() or "mixroom-native-auth"
APP_AUTH_AUDIENCE = os.environ.get("APP_AUTH_AUDIENCE", "").strip() or "mixroom-app"
AUTH_ACCOUNTS_TABLE = os.environ.get("AUTH_ACCOUNTS_TABLE", "").strip()
AUTH_SESSIONS_TABLE = os.environ.get("AUTH_SESSIONS_TABLE", "").strip()
AI_USAGE_STATE_TABLE = (
    os.environ.get("AI_USAGE_STATE_TABLE", "")
    or os.environ.get("AI_USAGE_METRICS_TABLE", "")
).strip()
AI_USAGE_EVENTS_TABLE = os.environ.get("AI_USAGE_EVENTS_TABLE", "").strip()
ENTITLEMENTS_TABLE = os.environ.get("ENTITLEMENTS_TABLE", "").strip()
LLM_MAX_OUTPUT_TOKENS = os.environ.get("LLM_MAX_OUTPUT_TOKENS", "").strip()
