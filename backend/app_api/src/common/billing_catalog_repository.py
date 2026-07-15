from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
import uuid
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        pass

    class BotoCoreError(Exception):
        pass

from . import billing_catalog, config

_PLAN_PREFIX = "billing_plan#"
_PRODUCT_PREFIX = "billing_product#"
_PROVIDER_PRODUCT_PREFIX = "billing_provider_product#"
_LEGACY_OFFER_PREFIX = "billing_offer#"
_SUPPORT_KEY = "billing_support#default"
_ONE_TIME_PRODUCT_PREFIX = "billing_one_time_product#"
_ONE_TIME_INTENT_PREFIX = "billing_one_time_intent#"
_ONE_TIME_CODE_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


class BillingCatalogRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.CATALOG_MAPPINGS_TABLE:
            self._table = self._ddb.Table(config.CATALOG_MAPPINGS_TABLE)

    def get_catalog(self) -> Dict[str, Any]:
        catalog = billing_catalog.default_catalog()
        if self._table is None:
            catalog["configurable"] = False
            catalog["updated_at"] = ""
            return catalog

        remote_plans: Dict[str, Dict[str, Any]] = {}
        remote_products: Dict[str, Dict[str, Any]] = {}
        remote_provider_products: Dict[str, Dict[str, Any]] = {}
        support = billing_catalog.default_support_settings()
        updated_at = ""

        for item in self._scan_managed_items():
            key = _safe_str(item.get("provider_product_key"))
            payload = item.get("payload") if isinstance(item.get("payload"), dict) else {}
            updated_at = max(updated_at, _safe_str(item.get("updated_at")))
            if key.startswith(_PLAN_PREFIX):
                code = _safe_str(item.get("code") or payload.get("code")).lower()
                if code:
                    remote_plans[code] = payload
            elif key.startswith(_PRODUCT_PREFIX):
                code = _safe_str(item.get("code") or payload.get("code")).lower()
                if code:
                    remote_products[code] = payload
            elif key.startswith(_PROVIDER_PRODUCT_PREFIX) or key.startswith(_LEGACY_OFFER_PREFIX):
                code = _safe_str(item.get("code") or payload.get("code")).lower()
                if code:
                    remote_provider_products[code] = payload
            elif key == _SUPPORT_KEY:
                support = billing_catalog.normalize_support_settings(payload)

        plans_by_code = {
            item["code"]: item for item in billing_catalog.default_catalog()["plans"]
        }
        for code, payload in remote_plans.items():
            if code in plans_by_code:
                plans_by_code[code] = {
                    **plans_by_code[code],
                    **payload,
                    "capabilities": billing_catalog.merge_capabilities(
                        plans_by_code[code].get("capabilities") or {},
                        payload.get("capabilities") or {},
                    ),
                    "limits": billing_catalog.merge_limits(
                        plans_by_code[code].get("limits") or {},
                        payload.get("limits") or {},
                    ),
                }
            else:
                plans_by_code[code] = payload

        products_by_code = {
            item["code"]: item for item in billing_catalog.default_catalog()["products"]
        }
        products_by_code.update(remote_products)

        provider_products_by_code = {
            item["code"]: item
            for item in billing_catalog.default_catalog()["provider_products"]
        }
        provider_products_by_code.update(remote_provider_products)

        return {
            "plans": billing_catalog.sort_plans(plans_by_code.values()),
            "products": billing_catalog.sort_products(products_by_code.values()),
            "provider_products": billing_catalog.sort_provider_products(
                provider_products_by_code.values()
            ),
            "support": support,
            "configurable": True,
            "updated_at": updated_at,
        }

    def get_product(self, product_code: str) -> Dict[str, Any]:
        catalog = self.get_catalog()
        return billing_catalog.catalog_product_by_code(product_code, catalog=catalog)

    def list_one_time_products(self) -> list[Dict[str, Any]]:
        return sorted((item.get("payload") or {} for item in self._scan_managed_items()
                       if _safe_str(item.get("provider_product_key")).startswith(_ONE_TIME_PRODUCT_PREFIX)),
                      key=lambda item: _safe_str(item.get("code")))

    def get_one_time_product(self, code: str, *, public_only: bool = False) -> Dict[str, Any]:
        code = _safe_str(code).lower()
        if not code or self._table is None:
            return {}
        try:
            item = self._table.get_item(Key={"provider_product_key": f"{_ONE_TIME_PRODUCT_PREFIX}{code}"}).get("Item") or {}
        except (BotoCoreError, ClientError):
            return {}
        product = item.get("payload") if isinstance(item.get("payload"), dict) else {}
        if public_only and (not product.get("enabled") or self._expired(product.get("expires_at"))):
            return {}
        return product

    def save_one_time_product(self, payload: Any, *, updated_by_user_id: str, updated_by_email: str) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Billing catalog mappings table is not configured.")
        if not isinstance(payload, dict):
            raise ValueError("One-time product payload must be an object.")
        code = _safe_str(payload.get("code")).lower()
        name = _safe_str(payload.get("order_name") or payload.get("name"))
        try: amount = int(payload.get("amount"))
        except (TypeError, ValueError): amount = 0
        if not _ONE_TIME_CODE_RE.fullmatch(code): raise ValueError("code must be a lowercase URL slug.")
        if not name or len(name) > 100: raise ValueError("order_name is required and must be at most 100 characters.")
        if amount < 1 or amount > 1_000_000_000: raise ValueError("amount must be a valid KRW amount.")
        expires_at = _safe_str(payload.get("expires_at"))
        if expires_at:
            try:
                expiry = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
                if expiry.tzinfo is None: raise ValueError
                expires_at = expiry.astimezone(timezone.utc).isoformat()
            except ValueError: raise ValueError("expires_at must be an ISO-8601 timestamp with timezone.")
        product = {"code": code, "order_name": name, "amount": amount, "currency": "KRW",
                   "enabled": bool(payload.get("enabled")), "expires_at": expires_at}
        now = _utc_now_iso()
        self._table.put_item(Item={"provider_product_key": f"{_ONE_TIME_PRODUCT_PREFIX}{code}", "kind": "one_time_product", "code": code, "payload": product, "updated_at": now, "updated_by_user_id": _safe_str(updated_by_user_id), "updated_by_email": _safe_str(updated_by_email).lower()})
        return product

    def create_one_time_checkout_intent(self, code: str) -> Dict[str, Any]:
        product = self.get_one_time_product(code, public_only=True)
        if not product: return {}
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(minutes=15)
        order_id = f"one-time-{product['code']}-{uuid.uuid4().hex}"
        intent = {"order_id": order_id, "product_code": product["code"], "order_name": product["order_name"], "amount": product["amount"], "currency": "KRW", "expires_at": expires_at.isoformat(), "ttl": int(expires_at.timestamp())}
        self._table.put_item(Item={"provider_product_key": f"{_ONE_TIME_INTENT_PREFIX}{order_id}", "kind": "one_time_checkout_intent", "code": product["code"], "payload": intent, "ttl": intent["ttl"], "updated_at": _utc_now_iso()})
        return intent

    def get_one_time_checkout_intent(self, order_id: str) -> Dict[str, Any]:
        if self._table is None or not _safe_str(order_id): return {}
        try: item = self._table.get_item(Key={"provider_product_key": f"{_ONE_TIME_INTENT_PREFIX}{_safe_str(order_id)}"}).get("Item") or {}
        except (BotoCoreError, ClientError): return {}
        intent = item.get("payload") if isinstance(item.get("payload"), dict) else {}
        return intent if intent and not self._expired(intent.get("expires_at")) else {}

    @staticmethod
    def _expired(value: Any) -> bool:
        if not _safe_str(value): return False
        try: return datetime.fromisoformat(_safe_str(value).replace("Z", "+00:00")).astimezone(timezone.utc) <= datetime.now(timezone.utc)
        except ValueError: return True

    def replace_catalog(
        self,
        *,
        plans: Any,
        products: Any,
        provider_products: Any = None,
        offers: Any = None,
        support: Any,
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Billing catalog mappings table is not configured.")

        normalized = billing_catalog.normalize_catalog_payload(
            plans=plans,
            products=products,
            provider_products=provider_products,
            offers=offers,
            support=support,
        )
        desired_items = self._build_items(
            normalized=normalized,
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        existing_keys = {
            _safe_str(item.get("provider_product_key"))
            for item in self._scan_managed_items()
            if _safe_str(item.get("provider_product_key"))
        }
        desired_keys = {
            _safe_str(item.get("provider_product_key"))
            for item in desired_items
            if _safe_str(item.get("provider_product_key"))
        }

        with self._table.batch_writer() as batch:
            for key in sorted(existing_keys - desired_keys):
                batch.delete_item(Key={"provider_product_key": key})
            for item in desired_items:
                batch.put_item(Item=item)

        return self.get_catalog()

    def _build_items(
        self,
        *,
        normalized: Dict[str, Any],
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> list[Dict[str, Any]]:
        now = _utc_now_iso()
        actor_user_id = _safe_str(updated_by_user_id)
        actor_email = _safe_str(updated_by_email).lower()
        items: list[Dict[str, Any]] = []
        for plan in normalized.get("plans") or []:
            items.append(
                {
                    "provider_product_key": f"{_PLAN_PREFIX}{plan['code']}",
                    "kind": "plan",
                    "code": plan["code"],
                    "payload": plan,
                    "updated_at": now,
                    "updated_by_user_id": actor_user_id,
                    "updated_by_email": actor_email,
                }
            )
        for product in normalized.get("products") or []:
            items.append(
                {
                    "provider_product_key": f"{_PRODUCT_PREFIX}{product['code']}",
                    "kind": "product",
                    "code": product["code"],
                    "payload": product,
                    "updated_at": now,
                    "updated_by_user_id": actor_user_id,
                    "updated_by_email": actor_email,
                }
            )
        for provider_product in normalized.get("provider_products") or []:
            items.append(
                {
                    "provider_product_key": (
                        f"{_PROVIDER_PRODUCT_PREFIX}{provider_product['code']}"
                    ),
                    "kind": "provider_product",
                    "code": provider_product["code"],
                    "payload": provider_product,
                    "updated_at": now,
                    "updated_by_user_id": actor_user_id,
                    "updated_by_email": actor_email,
                }
            )
        items.append(
            {
                "provider_product_key": _SUPPORT_KEY,
                "kind": "support",
                "code": "default",
                "payload": normalized.get("support") or {},
                "updated_at": now,
                "updated_by_user_id": actor_user_id,
                "updated_by_email": actor_email,
            }
        )
        return items

    def _scan_managed_items(self) -> list[Dict[str, Any]]:
        if self._table is None:
            return []
        items: list[Dict[str, Any]] = []
        start_key = None
        while True:
            kwargs: Dict[str, Any] = {}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            try:
                response = self._table.scan(**kwargs)
            except (BotoCoreError, ClientError):
                return []
            response_items = response.get("Items", [])
            if not isinstance(response_items, list):
                return []
            for item in response_items:
                if not isinstance(item, dict):
                    continue
                key = _safe_str(item.get("provider_product_key"))
                if self._is_managed_key(key):
                    items.append(item)
            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break
        return items

    def _is_managed_key(self, key: str) -> bool:
        return (
            key.startswith(_PLAN_PREFIX)
            or key.startswith(_PRODUCT_PREFIX)
            or key.startswith(_PROVIDER_PRODUCT_PREFIX)
            or key.startswith(_LEGACY_OFFER_PREFIX)
            or key == _SUPPORT_KEY
            or key.startswith(_ONE_TIME_PRODUCT_PREFIX)
            or key.startswith(_ONE_TIME_INTENT_PREFIX)
        )
