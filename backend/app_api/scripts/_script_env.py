from __future__ import annotations

import os


_DEFAULT_ENV = {
    "BILLING_EVENTS_TABLE": "billing-events",
    "SUBSCRIPTIONS_TABLE": "subscriptions",
    "ENTITLEMENTS_TABLE": "entitlements",
    "CATALOG_MAPPINGS_TABLE": "catalog-mappings",
    "FEATURE_FLAGS_TABLE": "feature-flags",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconcile-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
}


def prime_runtime_env() -> None:
    for key, value in _DEFAULT_ENV.items():
        os.environ.setdefault(key, value)
