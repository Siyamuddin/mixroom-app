import os

POSTHOG_API_KEY = os.environ.get("POSTHOG_API_KEY", "").strip()
POSTHOG_HOST = os.environ.get("POSTHOG_HOST", "").strip()
SENTRY_DSN = os.environ.get("SENTRY_DSN", "").strip()
ENVIRONMENT = os.environ.get("ENVIRONMENT", "").strip() or "dev"
APP_AUTH_SECRET_PARAMETER_NAME = os.environ.get(
    "APP_AUTH_SECRET_PARAMETER_NAME", ""
).strip()
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
AI_PROMPT_LIMIT_SETTINGS_TABLE = os.environ.get(
    "AI_PROMPT_LIMIT_SETTINGS_TABLE", ""
).strip()
ENTITLEMENTS_TABLE = os.environ.get("ENTITLEMENTS_TABLE", "").strip()
COLLABORATION_TABLE = os.environ.get("COLLABORATION_TABLE", "").strip()
LLM_MAX_OUTPUT_TOKENS = os.environ.get("LLM_MAX_OUTPUT_TOKENS", "").strip()
AI_RUNTIME_DEFAULT_MODEL = os.environ.get(
    "AI_RUNTIME_DEFAULT_MODEL",
    os.environ.get("LLM_MODEL", os.environ.get("OPENAI_MODEL", "gpt-4.1-mini")),
).strip() or "gpt-4.1-mini"
AI_V3_MODEL = os.environ.get("AI_V3_MODEL", "gpt-5.6-luna").strip() or "gpt-5.6-luna"
AI_V3_REASONING_EFFORT = (
    os.environ.get("AI_V3_REASONING_EFFORT", "low").strip().lower() or "low"
)
AI_CHAT_DEFAULT_TEMPERATURE = float(
    os.environ.get("AI_CHAT_DEFAULT_TEMPERATURE", "0.35") or "0.35"
)
VIDEO_EDITOR_DEFAULT_TEMPERATURE = float(
    os.environ.get("VIDEO_EDITOR_DEFAULT_TEMPERATURE", "0.1") or "0.1"
)
AI_CHAT_EXTENDED_PROMPT_CACHE_RETENTION_MODELS = frozenset(
    value.strip().lower()
    for value in os.environ.get(
        "AI_CHAT_EXTENDED_PROMPT_CACHE_RETENTION_MODELS",
        (
            "gpt-4.1,gpt-5,gpt-5-codex,gpt-5.1,gpt-5.1-codex,"
            "gpt-5.1-codex-mini,gpt-5.1-chat-latest,gpt-5.2"
        ),
    ).split(",")
    if value.strip()
)
