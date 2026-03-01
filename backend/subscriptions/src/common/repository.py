from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, Optional

import boto3
from boto3.dynamodb.conditions import Key

from . import config


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class BillingRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb")
        self._sqs = boto3.client("sqs")
        self._events = self._ddb.Table(config.BILLING_EVENTS_TABLE)
        self._subscriptions = self._ddb.Table(config.SUBSCRIPTIONS_TABLE)
        self._entitlements = self._ddb.Table(config.ENTITLEMENTS_TABLE)
        self._reconcile_jobs = self._ddb.Table(config.RECONCILIATION_JOBS_TABLE)

    def put_billing_event_if_new(self, event: Dict[str, Any]) -> bool:
        provider_event_key = event["provider_provider_event_id"]
        existing = self._events.query(
            IndexName="provider_event_idx",
            KeyConditionExpression=Key("provider_provider_event_id").eq(provider_event_key),
            Limit=1,
        )
        if existing.get("Items"):
            return False

        self._events.put_item(Item=event)
        return True

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
        self._subscriptions.put_item(Item=payload)

    def get_latest_subscription_for_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        result = self._subscriptions.query(
            IndexName="user_idx",
            KeyConditionExpression=Key("user_id").eq(user_id),
        )
        items = result.get("Items", [])
        if not items:
            return None
        items.sort(key=lambda x: x.get("updated_at", ""), reverse=True)
        return items[0]

    def put_entitlement(self, snapshot: Dict[str, Any]) -> None:
        payload = dict(snapshot)
        payload.setdefault("updated_at", _utc_now_iso())
        self._entitlements.put_item(Item=payload)

    def get_entitlement(self, user_id: str) -> Optional[Dict[str, Any]]:
        item = self._entitlements.get_item(Key={"user_id": user_id}).get("Item")
        return item

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

    def record_reconciliation_job(self, job: Dict[str, Any]) -> None:
        payload = dict(job)
        payload.setdefault("created_at", _utc_now_iso())
        self._reconcile_jobs.put_item(Item=payload)
