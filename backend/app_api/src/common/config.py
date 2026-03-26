import os

BILLING_EVENTS_TABLE = os.environ["BILLING_EVENTS_TABLE"]
SUBSCRIPTIONS_TABLE = os.environ["SUBSCRIPTIONS_TABLE"]
ENTITLEMENTS_TABLE = os.environ["ENTITLEMENTS_TABLE"]
USERS_TABLE = os.environ.get("USERS_TABLE", "").strip()
USERNAME_CLAIMS_TABLE = os.environ.get("USERNAME_CLAIMS_TABLE", "").strip()
AUTH_ACCOUNTS_TABLE = os.environ.get("AUTH_ACCOUNTS_TABLE", "").strip()
AUTH_SESSIONS_TABLE = os.environ.get("AUTH_SESSIONS_TABLE", "").strip()
AUTH_RATE_LIMITS_TABLE = os.environ.get("AUTH_RATE_LIMITS_TABLE", "").strip()
CATALOG_MAPPINGS_TABLE = os.environ["CATALOG_MAPPINGS_TABLE"]
CUSTOMER_LINKS_TABLE = os.environ["CUSTOMER_LINKS_TABLE"]
PURCHASE_TOKENS_TABLE = os.environ["PURCHASE_TOKENS_TABLE"]
RECONCILIATION_JOBS_TABLE = os.environ["RECONCILIATION_JOBS_TABLE"]
PROJECTION_QUEUE_URL = os.environ["PROJECTION_QUEUE_URL"]
USER_TOMBSTONES_TABLE = os.environ.get("USER_TOMBSTONES_TABLE", "").strip()
AI_USAGE_STATE_TABLE = os.environ.get("AI_USAGE_STATE_TABLE", "").strip()
AI_USAGE_EVENTS_TABLE = os.environ.get("AI_USAGE_EVENTS_TABLE", "").strip()
FEEDBACK_SUBMISSIONS_TABLE = os.environ.get("FEEDBACK_SUBMISSIONS_TABLE", "").strip()
ADMIN_ALLOWLIST_TABLE = os.environ.get("ADMIN_ALLOWLIST_TABLE", "").strip()
ADMIN_COGNITO_APP_CLIENT_ID = os.environ.get(
    "ADMIN_COGNITO_APP_CLIENT_ID", ""
).strip()
ADMIN_COGNITO_USER_POOL_ID = os.environ.get(
    "ADMIN_COGNITO_USER_POOL_ID", ""
).strip()
ADMIN_ALLOWED_EMAILS = os.environ.get("ADMIN_ALLOWED_EMAILS", "").strip()

ENFORCE_SUBSCRIPTIONS = os.environ.get("ENFORCE_SUBSCRIPTIONS", "false").lower() == "true"
ALLOW_STUDIO_TIER = os.environ.get("ALLOW_STUDIO_TIER", "false").lower() == "true"
HTTP_TIMEOUT_SECONDS = int(os.environ.get("HTTP_TIMEOUT_SECONDS", "20") or "20")
SECRET_CACHE_TTL_SECONDS = int(os.environ.get("SECRET_CACHE_TTL_SECONDS", "300") or "300")
APP_API_MAX_REQUEST_BYTES = int(
    os.environ.get("APP_API_MAX_REQUEST_BYTES", "200000") or "200000"
)

COGNITO_REGION = os.environ.get("COGNITO_REGION", "").strip()
COGNITO_USER_POOL_ID = os.environ.get("COGNITO_USER_POOL_ID", "").strip()
COGNITO_APP_CLIENT_ID = os.environ.get("COGNITO_APP_CLIENT_ID", "").strip()
SOCIAL_AUTH_SECRET_ARN = os.environ.get("SOCIAL_AUTH_SECRET_ARN", "").strip()
APP_AUTH_SECRET_ARN = os.environ.get("APP_AUTH_SECRET_ARN", "").strip()
APP_AUTH_ISSUER = os.environ.get("APP_AUTH_ISSUER", "").strip() or "mixroom-native-auth"
APP_AUTH_AUDIENCE = os.environ.get("APP_AUTH_AUDIENCE", "").strip() or "mixroom-app"
APP_AUTH_ACCESS_TOKEN_TTL_SECONDS = int(
    os.environ.get("APP_AUTH_ACCESS_TOKEN_TTL_SECONDS", "3600") or "3600"
)
APP_AUTH_REFRESH_TOKEN_TTL_SECONDS = int(
    os.environ.get("APP_AUTH_REFRESH_TOKEN_TTL_SECONDS", "2592000") or "2592000"
)
APP_AUTH_EMAIL_FROM_ADDRESS = os.environ.get(
    "APP_AUTH_EMAIL_FROM_ADDRESS", ""
).strip()
APP_AUTH_EMAIL_REPLY_TO_ADDRESS = os.environ.get(
    "APP_AUTH_EMAIL_REPLY_TO_ADDRESS", ""
).strip()
POSTMARK_SERVER_TOKEN = os.environ.get(
    "POSTMARK_SERVER_TOKEN", ""
).strip()
POSTMARK_SERVER_TOKEN_SECRET_ARN = os.environ.get(
    "POSTMARK_SERVER_TOKEN_SECRET_ARN", ""
).strip()
POSTMARK_API_BASE_URL = os.environ.get(
    "POSTMARK_API_BASE_URL", "https://api.postmarkapp.com"
).strip() or "https://api.postmarkapp.com"
POSTMARK_MESSAGE_STREAM = os.environ.get(
    "POSTMARK_MESSAGE_STREAM", ""
).strip()
GOOGLE_OAUTH_CLIENT_IDS = [
    value.strip()
    for value in os.environ.get("GOOGLE_OAUTH_CLIENT_IDS", "").split(",")
    if value.strip()
]

APPLE_BUNDLE_ID = os.environ.get("APPLE_BUNDLE_ID", "").strip()
APPLE_APP_ID = int(os.environ.get("APPLE_APP_ID", "0") or "0") or None
APPLE_ROOT_CA_SECRET_ARN = os.environ.get("APPLE_ROOT_CA_SECRET_ARN", "").strip()
APPLE_SHARED_SECRET_SECRET_ARN = os.environ.get(
    "APPLE_SHARED_SECRET_SECRET_ARN", ""
).strip()
APPLE_ENABLE_ONLINE_CHECKS = os.environ.get(
    "APPLE_ENABLE_ONLINE_CHECKS", "true"
).lower() == "true"

GOOGLE_PLAY_PACKAGE_NAME = os.environ.get("GOOGLE_PLAY_PACKAGE_NAME", "").strip()
GOOGLE_SERVICE_ACCOUNT_SECRET_ARN = os.environ.get(
    "GOOGLE_SERVICE_ACCOUNT_SECRET_ARN", ""
).strip()
GOOGLE_PUBSUB_AUDIENCE = os.environ.get("GOOGLE_PUBSUB_AUDIENCE", "").strip()
GOOGLE_PUBSUB_SERVICE_ACCOUNT_EMAIL = os.environ.get(
    "GOOGLE_PUBSUB_SERVICE_ACCOUNT_EMAIL", ""
).strip()

PADDLE_WEBHOOK_SECRET_ARN = os.environ.get("PADDLE_WEBHOOK_SECRET_ARN", "").strip()
TOSS_WEBHOOK_SECRET_ARN = os.environ.get("TOSS_WEBHOOK_SECRET_ARN", "").strip()

DEFAULT_CHECKOUT_URL = os.environ.get(
    "DEFAULT_CHECKOUT_URL",
    "https://www.mixroom.ai/subscribe",
)

POSTHOG_API_KEY = os.environ.get("POSTHOG_API_KEY", "").strip()
POSTHOG_HOST = os.environ.get("POSTHOG_HOST", "").strip()
SENTRY_DSN = os.environ.get("SENTRY_DSN", "").strip()
ENVIRONMENT = os.environ.get("ENVIRONMENT", "").strip() or "dev"
MINIMUM_SIGNUP_AGE_YEARS = int(
    os.environ.get("MINIMUM_SIGNUP_AGE_YEARS", "13") or "13"
)
