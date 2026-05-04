from __future__ import annotations

from datetime import datetime, timezone
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
_OFFER_PREFIX = "billing_offer#"
_SUPPORT_KEY = "billing_support#default"


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
        remote_offers: Dict[str, Dict[str, Any]] = {}
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
            elif key.startswith(_OFFER_PREFIX):
                code = _safe_str(item.get("code") or payload.get("code")).lower()
                if code:
                    remote_offers[code] = payload
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

        offers_by_code = {
            item["code"]: item for item in billing_catalog.default_catalog()["offers"]
        }
        offers_by_code.update(remote_offers)

        return {
            "plans": billing_catalog.sort_plans(plans_by_code.values()),
            "products": billing_catalog.sort_products(products_by_code.values()),
            "offers": billing_catalog.sort_offers(offers_by_code.values()),
            "support": support,
            "configurable": True,
            "updated_at": updated_at,
        }

    def get_product(self, product_code: str) -> Dict[str, Any]:
        catalog = self.get_catalog()
        return billing_catalog.catalog_product_by_code(product_code, catalog=catalog)

    def replace_catalog(
        self,
        *,
        plans: Any,
        products: Any,
        offers: Any,
        support: Any,
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Billing catalog mappings table is not configured.")

        normalized = billing_catalog.normalize_catalog_payload(
            plans=plans,
            products=products,
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
        for offer in normalized.get("offers") or []:
            items.append(
                {
                    "provider_product_key": f"{_OFFER_PREFIX}{offer['code']}",
                    "kind": "offer",
                    "code": offer["code"],
                    "payload": offer,
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
            or key.startswith(_OFFER_PREFIX)
            or key == _SUPPORT_KEY
        )
