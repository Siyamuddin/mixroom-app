from __future__ import annotations

import json
import hashlib
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, Optional

import boto3
try:
    from boto3.dynamodb.conditions import Attr, Key
except (ImportError, ModuleNotFoundError):  # pragma: no cover - local dev/test fallback
    Attr = None
    Key = None
try:
    from boto3.dynamodb.types import TypeSerializer
except (ImportError, ModuleNotFoundError):  # pragma: no cover - local dev/test fallback
    class TypeSerializer:  # type: ignore[override]
        def serialize(self, value: Any) -> Any:
            return value
from botocore.exceptions import ClientError

from . import config
from .models import normalize_plan_code, normalize_provider


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class UsernameClaimConflictError(Exception):
    pass


class BillingRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb")
        self._ddb_client = boto3.client("dynamodb")
        self._sqs = boto3.client("sqs")
        self._serializer = TypeSerializer()
        self._events = self._ddb.Table(config.BILLING_EVENTS_TABLE)
        self._subscriptions = self._ddb.Table(config.SUBSCRIPTIONS_TABLE)
        self._entitlements = self._ddb.Table(config.ENTITLEMENTS_TABLE)
        self._users = self._ddb.Table(config.USERS_TABLE) if config.USERS_TABLE else None
        self._username_claims = self._ddb.Table(config.USERNAME_CLAIMS_TABLE) if config.USERNAME_CLAIMS_TABLE else None
        self._auth_accounts = self._ddb.Table(config.AUTH_ACCOUNTS_TABLE) if config.AUTH_ACCOUNTS_TABLE else None
        self._auth_sessions = self._ddb.Table(config.AUTH_SESSIONS_TABLE) if config.AUTH_SESSIONS_TABLE else None
        self._reconcile_jobs = self._ddb.Table(config.RECONCILIATION_JOBS_TABLE)

    def put_billing_event_if_new(self, event: Dict[str, Any]) -> bool:
        try:
            self._events.put_item(
                Item=event,
                ConditionExpression="attribute_not_exists(event_id)",
            )
            return True
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code")
            if code == "ConditionalCheckFailedException":
                return False
            raise

    def get_billing_event(self, event_id: str) -> Optional[Dict[str, Any]]:
        item = self._events.get_item(Key={"event_id": event_id}).get("Item")
        return item

    def mark_billing_event_processed(self, event_id: str, result: str) -> None:
        self._events.update_item(
            Key={"event_id": event_id},
            UpdateExpression="SET processed_at = :processed_at, processing_result = :result",
            ExpressionAttributeValues={
                ":processed_at": _utc_now_iso(),
                ":result": result,
            },
        )

    def enqueue_projection(self, event_id: str) -> None:
        self._sqs.send_message(
            QueueUrl=config.PROJECTION_QUEUE_URL,
            MessageBody=json.dumps({"event_id": event_id}),
        )

    def upsert_subscription(self, record: Dict[str, Any]) -> None:
        payload = dict(record)
        payload.setdefault("updated_at", _utc_now_iso())
        payload["status_key"] = str(payload.get("status") or "").strip().lower() or "unknown"
        if payload.get("expires_at") is None or str(payload.get("expires_at") or "").strip() == "":
            payload.pop("expires_at", None)
        self._subscriptions.put_item(Item=payload)

    def get_subscription(self, subscription_id: str) -> Optional[Dict[str, Any]]:
        safe_id = str(subscription_id or "").strip()
        if not safe_id:
            return None
        item = self._subscriptions.get_item(Key={"subscription_id": safe_id}).get("Item")
        return item if isinstance(item, dict) else None

    def get_latest_subscription_for_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        items = self.list_subscriptions_for_user(user_id, limit=1)
        return items[0] if items else None

    def list_subscriptions_for_user(
        self,
        user_id: str,
        *,
        limit: Optional[int] = None,
    ) -> list[Dict[str, Any]]:
        items: list[Dict[str, Any]] = []
        try:
            kwargs: Dict[str, Any] = {
                "IndexName": "user_updated_idx",
                "KeyConditionExpression": Key("user_id").eq(user_id),
                "ScanIndexForward": False,
            }
            if limit is not None:
                kwargs["Limit"] = max(1, int(limit))
            result = self._subscriptions.query(**kwargs)
            items = result.get("Items", [])
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise
            result = self._subscriptions.query(
                IndexName="user_idx",
                KeyConditionExpression=Key("user_id").eq(user_id),
            )
            items = result.get("Items", [])
            items.sort(key=lambda x: x.get("updated_at", ""), reverse=True)
            if limit is not None:
                items = items[: max(1, int(limit))]
        return [item for item in items if isinstance(item, dict)]

    def get_catalog_mapping(self, provider: str, product_id: str) -> Optional[Dict[str, Any]]:
        key = {
            "provider_product_key": self.catalog_mapping_key(provider, product_id),
        }
        item = self._ddb.Table(config.CATALOG_MAPPINGS_TABLE).get_item(Key=key).get("Item")
        return item

    def put_customer_link(
        self,
        provider: str,
        customer_key: str,
        user_id: str,
        attributes: Optional[Dict[str, Any]] = None,
    ) -> None:
        payload = {
            "provider_customer_key": self.customer_link_key(provider, customer_key),
            "provider": normalize_provider(provider),
            "customer_key": customer_key,
            "user_id": user_id,
            "updated_at": _utc_now_iso(),
        }
        if attributes:
            payload.update(attributes)
        self._ddb.Table(config.CUSTOMER_LINKS_TABLE).put_item(Item=payload)

    def get_customer_link(self, provider: str, customer_key: str) -> Optional[Dict[str, Any]]:
        key = {
            "provider_customer_key": self.customer_link_key(provider, customer_key),
        }
        return self._ddb.Table(config.CUSTOMER_LINKS_TABLE).get_item(Key=key).get("Item")

    def put_purchase_token(
        self,
        provider: str,
        token: str,
        attributes: Optional[Dict[str, Any]] = None,
    ) -> None:
        payload = {
            "provider_token_hash": self.purchase_token_hash(provider, token),
            "provider": normalize_provider(provider),
            "updated_at": _utc_now_iso(),
        }
        if attributes:
            payload.update(attributes)
        self._ddb.Table(config.PURCHASE_TOKENS_TABLE).put_item(Item=payload)

    def get_purchase_token(self, provider: str, token: str) -> Optional[Dict[str, Any]]:
        key = {
            "provider_token_hash": self.purchase_token_hash(provider, token),
        }
        return self._ddb.Table(config.PURCHASE_TOKENS_TABLE).get_item(Key=key).get("Item")

    def put_entitlement(self, snapshot: Dict[str, Any]) -> None:
        payload = dict(snapshot)
        payload.setdefault("updated_at", _utc_now_iso())
        payload["status_key"] = str(payload.get("status") or "").strip().lower() or "unknown"
        # The existing GSI attribute is named tier_key in deployed tables; it now
        # stores plan codes to avoid an infrastructure migration for the rename.
        payload["tier_key"] = normalize_plan_code(
            payload.get("plan_code") or payload.get("tier") or "free"
        )
        self._entitlements.put_item(Item=payload)

    def get_entitlement(self, user_id: str) -> Optional[Dict[str, Any]]:
        item = self._entitlements.get_item(Key={"user_id": user_id}).get("Item")
        return item

    def delete_entitlement(self, user_id: str) -> None:
        self._entitlements.delete_item(Key={"user_id": user_id})

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        if self._users is None:
            return None
        item = self._users.get_item(Key={"user_id": user_id}).get("Item")
        return item

    def get_user_profile_by_email(self, email_lc: str) -> Optional[Dict[str, Any]]:
        normalized = str(email_lc or "").strip().lower()
        if not normalized or self._users is None:
            return None
        try:
            result = self._users.query(
                IndexName="email_idx",
                KeyConditionExpression=Key("email_lc").eq(normalized),
                Limit=1,
            )
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise
            return None
        items = result.get("Items", [])
        if not items:
            return None
        item = items[0]
        return item if isinstance(item, dict) else None

    def list_recent_user_profiles(self, *, limit: int = 24) -> list[Dict[str, Any]]:
        if self._users is None:
            return []
        try:
            result = self._users.query(
                IndexName="status_last_seen_idx",
                KeyConditionExpression=Key("profile_status").eq("active"),
                ScanIndexForward=False,
                Limit=max(1, int(limit)),
            )
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise
            result = self._users.scan(Limit=max(1, int(limit)))
        items = result.get("Items", [])
        return [item for item in items if isinstance(item, dict)]

    def get_username_claim(self, username_lc: str) -> Optional[Dict[str, Any]]:
        normalized = str(username_lc or "").strip().lower()
        if not normalized or self._username_claims is None:
            return None
        return self._username_claims.get_item(Key={"username_lc": normalized}).get("Item")

    def get_user_profile_by_username(self, username_lc: str) -> Optional[Dict[str, Any]]:
        claim = self.get_username_claim(username_lc)
        if not claim:
            return None
        user_id = str(claim.get("user_id") or "").strip()
        if not user_id:
            return None
        return self.get_user_profile(user_id)

    def delete_user_profile(self, user_id: str) -> None:
        if self._users is None:
            return
        self._users.delete_item(Key={"user_id": user_id})

    def get_auth_account(self, user_id: str) -> Optional[Dict[str, Any]]:
        if self._auth_accounts is None:
            return None
        item = self._auth_accounts.get_item(Key={"user_id": user_id}).get("Item")
        return item if isinstance(item, dict) else None

    def get_auth_account_by_email(self, email_lc: str) -> Optional[Dict[str, Any]]:
        normalized = str(email_lc or "").strip().lower()
        if not normalized or self._auth_accounts is None:
            return None
        try:
            result = self._auth_accounts.query(
                IndexName="email_idx",
                KeyConditionExpression=Key("email_lc").eq(normalized),
                Limit=1,
            )
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise
            return None
        items = result.get("Items") or []
        if not items:
            return None
        item = items[0]
        return item if isinstance(item, dict) else None

    def put_auth_account(self, record: Dict[str, Any]) -> None:
        if self._auth_accounts is None:
            raise RuntimeError("AUTH_ACCOUNTS_TABLE is not configured.")
        payload = dict(record)
        payload.setdefault("updated_at", _utc_now_iso())
        self._auth_accounts.put_item(Item=payload)

    def delete_auth_account(self, user_id: str) -> None:
        if self._auth_accounts is None:
            return
        self._auth_accounts.delete_item(Key={"user_id": user_id})

    def get_auth_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        if self._auth_sessions is None:
            return None
        item = self._auth_sessions.get_item(Key={"session_id": session_id}).get("Item")
        return item if isinstance(item, dict) else None

    def put_auth_session(self, record: Dict[str, Any]) -> None:
        if self._auth_sessions is None:
            raise RuntimeError("AUTH_SESSIONS_TABLE is not configured.")
        payload = dict(record)
        payload.setdefault("updated_at", _utc_now_iso())
        self._auth_sessions.put_item(Item=payload)

    def delete_auth_session(self, session_id: str) -> None:
        if self._auth_sessions is None:
            return
        self._auth_sessions.delete_item(Key={"session_id": session_id})

    def list_auth_sessions_for_user(self, user_id: str) -> list[Dict[str, Any]]:
        if self._auth_sessions is None:
            return []
        items: list[Dict[str, Any]] = []
        try:
            start_key = None
            while True:
                kwargs: Dict[str, Any] = {
                    "IndexName": "user_idx",
                    "KeyConditionExpression": Key("user_id").eq(user_id),
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                result = self._auth_sessions.query(**kwargs)
                items.extend(
                    item for item in result.get("Items", []) if isinstance(item, dict)
                )
                start_key = result.get("LastEvaluatedKey")
                if not start_key:
                    break
            return items
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise

        start_key = None
        while True:
            kwargs = {"FilterExpression": Attr("user_id").eq(user_id)}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            result = self._auth_sessions.scan(**kwargs)
            items.extend(
                item for item in result.get("Items", []) if isinstance(item, dict)
            )
            start_key = result.get("LastEvaluatedKey")
            if not start_key:
                break
        return items

    def delete_auth_sessions_for_user(self, user_id: str) -> None:
        if self._auth_sessions is None:
            return
        items = self.list_auth_sessions_for_user(user_id)
        if not items:
            return
        with self._auth_sessions.batch_writer() as batch:
            for item in items:
                session_id = str(item.get("session_id") or "").strip()
                if not session_id:
                    continue
                batch.delete_item(Key={"session_id": session_id})

    def upsert_user_profile(
        self,
        record: Dict[str, Any],
        *,
        previous_username_lc: Optional[str] = None,
    ) -> None:
        if self._users is None:
            raise RuntimeError("USERS_TABLE is not configured.")
        if config.USERNAME_CLAIMS_TABLE and self._username_claims is None:
            raise RuntimeError("USERNAME_CLAIMS_TABLE is not configured.")
        payload = dict(record)
        payload.setdefault("updated_at", _utc_now_iso())
        new_username_lc = str(payload.get("username_lc") or "").strip().lower() or None
        old_username_lc = str(previous_username_lc or "").strip().lower() or None

        if not config.USERNAME_CLAIMS_TABLE:
            self._users.put_item(Item=payload)
            return

        transact_items = []
        if new_username_lc:
            transact_items.append(
                {
                    "Put": {
                        "TableName": config.USERNAME_CLAIMS_TABLE,
                        "Item": self._serialize_item(
                            {
                                "username_lc": new_username_lc,
                                "user_id": str(payload.get("user_id") or "").strip(),
                                "updated_at": payload["updated_at"],
                            }
                        ),
                        "ConditionExpression": "attribute_not_exists(username_lc) OR user_id = :user_id",
                        "ExpressionAttributeValues": {
                            ":user_id": {"S": str(payload.get("user_id") or "").strip()},
                        },
                    }
                }
            )

        transact_items.append(
            {
                "Put": {
                    "TableName": config.USERS_TABLE,
                    "Item": self._serialize_item(payload),
                }
            }
        )

        if old_username_lc and old_username_lc != new_username_lc:
            transact_items.append(
                {
                    "Delete": {
                        "TableName": config.USERNAME_CLAIMS_TABLE,
                        "Key": self._serialize_item({"username_lc": old_username_lc}),
                        "ConditionExpression": "attribute_not_exists(username_lc) OR user_id = :user_id",
                        "ExpressionAttributeValues": {
                            ":user_id": {"S": str(payload.get("user_id") or "").strip()},
                        },
                    }
                }
            )

        try:
            self._ddb_client.transact_write_items(TransactItems=transact_items)
        except ClientError as exc:
            error_code = exc.response.get("Error", {}).get("Code")
            if error_code == "TransactionCanceledException":
                raise UsernameClaimConflictError("That username is already taken.") from exc
            raise

    def update_user_newsletter_subscription(
        self,
        user_id: str,
        *,
        newsletter_opt_in: bool,
        newsletter_opt_in_at: Optional[str],
    ) -> None:
        if self._users is None:
            raise RuntimeError("USERS_TABLE is not configured.")
        normalized_user_id = str(user_id or "").strip()
        if not normalized_user_id:
            raise ValueError("User id is required.")
        self._users.update_item(
            Key={"user_id": normalized_user_id},
            UpdateExpression=(
                "SET newsletter_opt_in = :newsletter_opt_in, "
                "newsletter_opt_in_at = :newsletter_opt_in_at, "
                "updated_at = :updated_at"
            ),
            ExpressionAttributeValues={
                ":newsletter_opt_in": bool(newsletter_opt_in),
                ":newsletter_opt_in_at": newsletter_opt_in_at,
                ":updated_at": _utc_now_iso(),
            },
            ConditionExpression="attribute_exists(user_id)",
        )

    def delete_subscriptions_for_user(self, user_id: str) -> None:
        items = self.list_subscriptions_for_user(user_id)
        if not items:
            return
        with self._subscriptions.batch_writer() as batch:
            for item in items:
                subscription_id = str(item.get("subscription_id") or "").strip()
                if not subscription_id:
                    continue
                batch.delete_item(Key={"subscription_id": subscription_id})

    def scan_entitlements(self) -> Iterable[Dict[str, Any]]:
        start_key = None
        while True:
            kwargs: Dict[str, Any] = {}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            result = self._entitlements.scan(**kwargs)
            for item in result.get("Items", []):
                yield item
            start_key = result.get("LastEvaluatedKey")
            if not start_key:
                break

    def scan_users(self) -> Iterable[Dict[str, Any]]:
        if self._users is None:
            return
        start_key = None
        while True:
            kwargs: Dict[str, Any] = {}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            result = self._users.scan(**kwargs)
            for item in result.get("Items", []):
                yield item
            start_key = result.get("LastEvaluatedKey")
            if not start_key:
                break

    def scan_subscriptions(self) -> Iterable[Dict[str, Any]]:
        start_key = None
        while True:
            kwargs: Dict[str, Any] = {}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            result = self._subscriptions.scan(**kwargs)
            for item in result.get("Items", []):
                yield item
            start_key = result.get("LastEvaluatedKey")
            if not start_key:
                break

    def delete_username_claim(self, username_lc: Optional[str]) -> None:
        normalized = str(username_lc or "").strip().lower()
        if not normalized or self._username_claims is None:
            return
        self._username_claims.delete_item(Key={"username_lc": normalized})

    def delete_customer_links_for_user(self, user_id: str) -> None:
        items = self.list_customer_links_for_user(user_id)
        if not items:
            return
        table = self._ddb.Table(config.CUSTOMER_LINKS_TABLE)
        with table.batch_writer() as batch:
            for item in items:
                provider_customer_key = str(item.get("provider_customer_key") or "").strip()
                if not provider_customer_key:
                    continue
                batch.delete_item(Key={"provider_customer_key": provider_customer_key})

    def delete_purchase_tokens_for_user(self, user_id: str) -> None:
        items = self.list_purchase_tokens_for_user(user_id)
        if not items:
            return
        table = self._ddb.Table(config.PURCHASE_TOKENS_TABLE)
        with table.batch_writer() as batch:
            for item in items:
                provider_token_hash = str(item.get("provider_token_hash") or "").strip()
                if not provider_token_hash:
                    continue
                batch.delete_item(Key={"provider_token_hash": provider_token_hash})

    def delete_user_account_data(
        self,
        user_id: str,
        *,
        username_lc: Optional[str] = None,
    ) -> None:
        self.delete_auth_sessions_for_user(user_id)
        self.delete_auth_account(user_id)
        self.delete_subscriptions_for_user(user_id)
        self.delete_entitlement(user_id)
        self.delete_customer_links_for_user(user_id)
        self.delete_purchase_tokens_for_user(user_id)
        self.delete_user_profile(user_id)
        self.delete_username_claim(username_lc)

    def list_customer_links_for_user(self, user_id: str) -> list[Dict[str, Any]]:
        table = self._ddb.Table(config.CUSTOMER_LINKS_TABLE)
        items: list[Dict[str, Any]] = []
        try:
            start_key = None
            while True:
                kwargs: Dict[str, Any] = {
                    "IndexName": "user_idx",
                    "KeyConditionExpression": Key("user_id").eq(user_id),
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                result = table.query(**kwargs)
                items.extend(
                    item for item in result.get("Items", []) if isinstance(item, dict)
                )
                start_key = result.get("LastEvaluatedKey")
                if not start_key:
                    break
            return items
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise

        start_key = None
        while True:
            kwargs = {"FilterExpression": Attr("user_id").eq(user_id)}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            result = table.scan(**kwargs)
            items.extend(
                item for item in result.get("Items", []) if isinstance(item, dict)
            )
            start_key = result.get("LastEvaluatedKey")
            if not start_key:
                break
        return items

    def list_purchase_tokens_for_user(self, user_id: str) -> list[Dict[str, Any]]:
        table = self._ddb.Table(config.PURCHASE_TOKENS_TABLE)
        items: list[Dict[str, Any]] = []
        try:
            start_key = None
            while True:
                kwargs: Dict[str, Any] = {
                    "IndexName": "user_idx",
                    "KeyConditionExpression": Key("user_id").eq(user_id),
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                result = table.query(**kwargs)
                items.extend(
                    item for item in result.get("Items", []) if isinstance(item, dict)
                )
                start_key = result.get("LastEvaluatedKey")
                if not start_key:
                    break
            return items
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise

        start_key = None
        while True:
            kwargs = {"FilterExpression": Attr("user_id").eq(user_id)}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            result = table.scan(**kwargs)
            items.extend(
                item for item in result.get("Items", []) if isinstance(item, dict)
            )
            start_key = result.get("LastEvaluatedKey")
            if not start_key:
                break
        return items

    def list_expired_subscriptions_for_statuses(
        self,
        *,
        statuses: Iterable[str],
        expires_before: str,
    ) -> Iterable[Dict[str, Any]]:
        normalized_statuses = [
            str(status or "").strip().lower()
            for status in statuses
            if str(status or "").strip()
        ]
        seen_subscription_ids: set[str] = set()
        try:
            for status in normalized_statuses:
                start_key = None
                while True:
                    kwargs: Dict[str, Any] = {
                        "IndexName": "status_expires_idx",
                        "KeyConditionExpression": (
                            Key("status_key").eq(status)
                            & Key("expires_at").lt(expires_before)
                        ),
                    }
                    if start_key:
                        kwargs["ExclusiveStartKey"] = start_key
                    result = self._subscriptions.query(**kwargs)
                    for item in result.get("Items", []):
                        if not isinstance(item, dict):
                            continue
                        subscription_id = str(item.get("subscription_id") or "").strip()
                        if not subscription_id or subscription_id in seen_subscription_ids:
                            continue
                        seen_subscription_ids.add(subscription_id)
                        yield item
                    start_key = result.get("LastEvaluatedKey")
                    if not start_key:
                        break
            return
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code != "ValidationException":
                raise

        for sub in self.scan_subscriptions():
            status = str(sub.get("status") or "").strip().lower()
            expires_at = str(sub.get("expires_at") or "").strip()
            if status in normalized_statuses and expires_at and expires_at < expires_before:
                yield sub

    def record_reconciliation_job(self, job: Dict[str, Any]) -> None:
        payload = dict(job)
        payload.setdefault("created_at", _utc_now_iso())
        self._reconcile_jobs.put_item(Item=payload)

    def get_reconciliation_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        safe_id = str(job_id or "").strip()
        if not safe_id:
            return None
        item = self._reconcile_jobs.get_item(Key={"job_id": safe_id}).get("Item")
        return item if isinstance(item, dict) else None

    def record_reconciliation_job_once(self, job: Dict[str, Any]) -> bool:
        payload = dict(job)
        payload.setdefault("created_at", _utc_now_iso())
        try:
            self._reconcile_jobs.put_item(
                Item=payload,
                ConditionExpression="attribute_not_exists(job_id)",
            )
            return True
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code") or "").strip()
            if code == "ConditionalCheckFailedException":
                return False
            raise

    @staticmethod
    def catalog_mapping_key(provider: str, product_id: str) -> str:
        return f"{normalize_provider(provider)}:{(product_id or '').strip()}"

    @staticmethod
    def customer_link_key(provider: str, customer_key: str) -> str:
        return f"{normalize_provider(provider)}:{(customer_key or '').strip()}"

    @staticmethod
    def purchase_token_hash(provider: str, token: str) -> str:
        raw = f"{normalize_provider(provider)}:{(token or '').strip()}".encode("utf-8")
        return hashlib.sha256(raw).hexdigest()

    def _serialize_item(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        return {
            key: self._serializer.serialize(value)
            for key, value in payload.items()
            if value is not None
        }
