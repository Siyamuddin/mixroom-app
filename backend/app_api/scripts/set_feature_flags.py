#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from typing import Any, Dict

_FLAG_SET_KEY = "feature_flags#default"
_FLAGS = (
    "account_plan_billing_enabled",
    "subscription_enforcement_enabled",
    "iap_purchases_enabled",
)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_bool(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"true", "1", "yes", "y", "on"}:
        return True
    if normalized in {"false", "0", "no", "n", "off"}:
        return False
    raise argparse.ArgumentTypeError("Expected true or false.")


def _build_item(args: argparse.Namespace) -> Dict[str, Any]:
    flags = {
        "account_plan_billing_enabled": args.account_plan_billing_enabled,
        "subscription_enforcement_enabled": args.subscription_enforcement_enabled,
        "iap_purchases_enabled": args.iap_purchases_enabled,
    }
    return {
        "flag_set_key": _FLAG_SET_KEY,
        "kind": "feature_flags",
        "payload": {"flags": flags},
        "updated_at": _utc_now_iso(),
        "updated_by_user_id": args.updated_by_user_id,
        "updated_by_email": args.updated_by_email.strip().lower(),
    }


def _apply_item(table_name: str, item: Dict[str, Any]) -> int:
    try:
        import boto3
    except ImportError:
        print(
            "boto3 is required for --apply. Install it first, or run without "
            "--apply to print the DynamoDB item.",
            file=sys.stderr,
        )
        return 2

    table = boto3.resource("dynamodb").Table(table_name)
    table.put_item(Item=item)
    print(f"Wrote feature flags to {table_name}.")
    return 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Print or apply Mixroom feature flag values."
    )
    parser.add_argument(
        "--stage",
        default="prod",
        help="Stage suffix used when deriving the DynamoDB table name.",
    )
    parser.add_argument(
        "--table-name",
        default="",
        help="Override the DynamoDB table name instead of deriving it from --stage.",
    )
    for flag in _FLAGS:
        parser.add_argument(
            f"--{flag.replace('_', '-')}",
            type=_parse_bool,
            required=True,
            help=f"Set {flag}. Use true or false.",
        )
    parser.add_argument(
        "--updated-by-user-id",
        default="script",
        help="Audit user id written to the item.",
    )
    parser.add_argument(
        "--updated-by-email",
        default="andrew@mixroom.ai",
        help="Audit email written to the item.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write the item directly into DynamoDB.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    item = _build_item(args)
    table_name = args.table_name or f"mixroom-feature-flags-{args.stage}"
    if not args.apply:
        print(json.dumps({"table_name": table_name, "item": item}, indent=2))
        return 0
    return _apply_item(table_name, item)


if __name__ == "__main__":
    raise SystemExit(main())
