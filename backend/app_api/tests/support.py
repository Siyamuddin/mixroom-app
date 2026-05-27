import json
import os
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))
if str(_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_ROOT / "src"))

_REQUIRED_ENV = {
    "BILLING_EVENTS_TABLE": "billing-events",
    "SUBSCRIPTIONS_TABLE": "subscriptions",
    "ENTITLEMENTS_TABLE": "entitlements",
    "USERS_TABLE": "users",
    "USERNAME_CLAIMS_TABLE": "username-claims",
    "CATALOG_MAPPINGS_TABLE": "catalog-mappings",
    "FEATURE_FLAGS_TABLE": "feature-flags",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconcile-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
    "USER_TOMBSTONES_TABLE": "user-tombstones",
    "APPLE_BUNDLE_ID": "ai.mixroom.test",
    "APPLE_APP_ID": "123456789",
    "APP_AUTH_SECRET_ARN": "app-auth-secret",
    "GOOGLE_PLAY_PACKAGE_NAME": "ai.mixroom.test",
}
for key, value in _REQUIRED_ENV.items():
    os.environ.setdefault(key, value)

if "boto3" not in sys.modules:
    boto3_stub = ModuleType("boto3")
    boto3_stub.client = mock.Mock(return_value=mock.Mock())
    boto3_stub.resource = mock.Mock(
        return_value=SimpleNamespace(Table=mock.Mock(return_value=mock.Mock()))
    )
    sys.modules["boto3"] = boto3_stub

if "boto3.dynamodb" not in sys.modules:
    dynamodb_stub = ModuleType("boto3.dynamodb")
    conditions_stub = ModuleType("boto3.dynamodb.conditions")
    conditions_stub.Attr = mock.Mock()
    conditions_stub.Key = mock.Mock()
    types_stub = ModuleType("boto3.dynamodb.types")

    class _TypeSerializer:
        def serialize(self, value):
            return value

    types_stub.TypeSerializer = _TypeSerializer
    dynamodb_stub.conditions = conditions_stub
    dynamodb_stub.types = types_stub
    sys.modules["boto3.dynamodb"] = dynamodb_stub
    sys.modules["boto3.dynamodb.conditions"] = conditions_stub
    sys.modules["boto3.dynamodb.types"] = types_stub

if "botocore.exceptions" not in sys.modules:
    botocore_stub = ModuleType("botocore")
    exceptions_stub = ModuleType("botocore.exceptions")

    class _BotoCoreError(Exception):
        pass

    class _ClientError(Exception):
        def __init__(self, response: dict, operation_name: str = "") -> None:
            super().__init__(operation_name)
            self.response = response

    exceptions_stub.BotoCoreError = _BotoCoreError
    exceptions_stub.ClientError = _ClientError
    botocore_stub.exceptions = exceptions_stub
    sys.modules["botocore"] = botocore_stub
    sys.modules["botocore.exceptions"] = exceptions_stub


class FakeBillingRepo:
    def __init__(self):
        self.billing_events = {}
        self.subscriptions = {}
        self.entitlements = {}
        self.user_profiles = {}
        self.auth_accounts = {}
        self.catalog_mappings = {}
        self.customer_links = {}
        self.purchase_tokens = {}
        self.queued_projection_ids = []
        self.reconciliation_jobs = []
        self.user_profile_upserts = []
        self.user_profile_newsletter_updates = []

    def put_billing_event_if_new(self, event):
        event_id = str(event["event_id"])
        if event_id in self.billing_events:
            return False
        self.billing_events[event_id] = dict(event)
        return True

    def get_billing_event(self, event_id):
        event = self.billing_events.get(event_id)
        return dict(event) if isinstance(event, dict) else None

    def mark_billing_event_processed(self, event_id, result):
        if event_id in self.billing_events:
            self.billing_events[event_id]["processing_result"] = result
            self.billing_events[event_id]["processed_at"] = "processed"

    def enqueue_projection(self, event_id):
        self.queued_projection_ids.append(event_id)

    def upsert_subscription(self, record):
        self.subscriptions[str(record["subscription_id"])] = dict(record)

    def get_subscription(self, subscription_id):
        item = self.subscriptions.get(str(subscription_id))
        return dict(item) if isinstance(item, dict) else None

    def get_latest_subscription_for_user(self, user_id):
        matches = self.list_subscriptions_for_user(user_id)
        if not matches:
            return None
        matches.sort(key=lambda item: str(item.get("updated_at") or ""), reverse=True)
        return dict(matches[0])

    def list_subscriptions_for_user(self, user_id):
        return [
            dict(item)
            for item in self.subscriptions.values()
            if str(item.get("user_id") or "") == user_id
        ]

    def get_catalog_mapping(self, provider, product_id):
        item = self.catalog_mappings.get(f"{provider}:{product_id}")
        return dict(item) if isinstance(item, dict) else None

    def put_customer_link(self, provider, customer_key, user_id, attributes=None):
        payload = {
            "provider": provider,
            "customer_key": customer_key,
            "user_id": user_id,
        }
        if attributes:
            payload.update(attributes)
        self.customer_links[f"{provider}:{customer_key}"] = payload

    def get_customer_link(self, provider, customer_key):
        item = self.customer_links.get(f"{provider}:{customer_key}")
        return dict(item) if isinstance(item, dict) else None

    def list_customer_links_for_user(self, user_id):
        return [
            dict(item)
            for item in self.customer_links.values()
            if str(item.get("user_id") or "") == user_id
        ]

    def put_purchase_token(self, provider, token, attributes=None):
        payload = {
            "provider": provider,
        }
        if attributes:
            payload.update(attributes)
        self.purchase_tokens[f"{provider}:{token}"] = payload

    def get_purchase_token(self, provider, token):
        item = self.purchase_tokens.get(f"{provider}:{token}")
        return dict(item) if isinstance(item, dict) else None

    def put_entitlement(self, snapshot):
        self.entitlements[str(snapshot["user_id"])] = dict(snapshot)

    def get_entitlement(self, user_id):
        item = self.entitlements.get(user_id)
        return dict(item) if isinstance(item, dict) else None

    def delete_entitlement(self, user_id):
        self.entitlements.pop(user_id, None)

    def get_user_profile(self, user_id):
        item = self.user_profiles.get(user_id)
        return dict(item) if isinstance(item, dict) else None

    def get_user_profile_by_email(self, email_lc):
        normalized = str(email_lc or "").strip().lower()
        for item in self.user_profiles.values():
            if str(item.get("email_lc") or item.get("email") or "").strip().lower() == normalized:
                return dict(item)
        return None

    def get_auth_account(self, user_id):
        item = self.auth_accounts.get(user_id)
        return dict(item) if isinstance(item, dict) else None

    def get_auth_account_by_email(self, email_lc):
        normalized = str(email_lc or "").strip().lower()
        for item in self.auth_accounts.values():
            if str(item.get("email_lc") or item.get("email") or "").strip().lower() == normalized:
                return dict(item)
        return None

    def upsert_user_profile(self, profile, *, previous_username_lc=None):
        payload = dict(profile)
        self.user_profiles[str(payload["user_id"])] = payload
        self.user_profile_upserts.append(
            {
                "profile": payload,
                "previous_username_lc": previous_username_lc,
            }
        )

    def update_user_newsletter_subscription(
        self,
        user_id,
        *,
        newsletter_opt_in,
        newsletter_opt_in_at,
    ):
        payload = dict(self.user_profiles[str(user_id)])
        payload["newsletter_opt_in"] = bool(newsletter_opt_in)
        payload["newsletter_opt_in_at"] = newsletter_opt_in_at
        payload["updated_at"] = "updated"
        self.user_profiles[str(user_id)] = payload
        self.user_profile_newsletter_updates.append(
            {
                "user_id": str(user_id),
                "newsletter_opt_in": bool(newsletter_opt_in),
                "newsletter_opt_in_at": newsletter_opt_in_at,
            }
        )

    def scan_subscriptions(self):
        for item in self.subscriptions.values():
            yield dict(item)

    def scan_entitlements(self):
        for item in self.entitlements.values():
            yield dict(item)

    def record_reconciliation_job(self, job):
        self.reconciliation_jobs.append(dict(job))

    def get_reconciliation_job(self, job_id):
        safe_id = str(job_id or "")
        for item in self.reconciliation_jobs:
            if str(item.get("job_id") or "") == safe_id:
                return dict(item)
        return None

    def record_reconciliation_job_once(self, job):
        job_id = str(job.get("job_id") or "")
        if any(str(item.get("job_id") or "") == job_id for item in self.reconciliation_jobs):
            return False
        self.reconciliation_jobs.append(dict(job))
        return True


class FakeEventBridge:
    def __init__(self):
        self.entries = []

    def put_events(self, *, Entries):
        self.entries.extend(Entries)
        return {"FailedEntryCount": 0, "Entries": [{"EventId": "evt-1"}]}


def decode_json_response(response):
    return json.loads(response["body"])
