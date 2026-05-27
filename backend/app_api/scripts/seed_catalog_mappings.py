#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from typing import Dict, List


def _build_record(
    provider: str,
    product_id: str,
    plan_code: str,
    product_code: str,
) -> Dict[str, str]:
    return {
        "provider_product_key": f"{provider}:{product_id}",
        "provider": provider,
        "product_id": product_id,
        "plan_code": plan_code,
        "product_code": product_code,
    }


def _build_records(args: argparse.Namespace) -> List[Dict[str, str]]:
    records: List[Dict[str, str]] = []

    if args.apple_product_id:
        records.append(
            _build_record(
                "apple",
                args.apple_product_id,
                args.apple_plan_code,
                args.apple_product_code,
            )
        )
    if args.google_product_id:
        records.append(
            _build_record(
                "google",
                args.google_product_id,
                args.google_plan_code,
                args.google_product_code,
            )
        )
    if args.apple_studio_product_id:
        records.append(
            _build_record(
                "apple",
                args.apple_studio_product_id,
                "studio",
                "studio_monthly",
            )
        )
    if args.google_studio_product_id:
        records.append(
            _build_record(
                "google",
                args.google_studio_product_id,
                "studio",
                "studio_monthly",
            )
        )

    return records


def _apply_records(table_name: str, records: List[Dict[str, str]]) -> int:
    try:
        import boto3
    except ImportError:
        print(
            "boto3 is required for --apply. Install it first, or run without "
            "--apply to just print the seed JSON.",
            file=sys.stderr,
        )
        return 2

    table = boto3.resource("dynamodb").Table(table_name)
    for record in records:
        table.put_item(Item=record)
    print(f"Wrote {len(records)} catalog mapping rows to {table_name}.")
    return 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Print or apply the minimal Mixroom subscription catalog mappings."
        )
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
    parser.add_argument(
        "--apple-product-id",
        default="mixroom_producer_monthly",
        help="Apple product ID for the default Producer monthly product.",
    )
    parser.add_argument(
        "--google-product-id",
        default="mixroom_producer_monthly",
        help="Google product ID for the default Producer monthly product.",
    )
    parser.add_argument(
        "--apple-plan-code",
        choices=("free", "starter", "producer", "studio", "enterprise", "education"),
        default="producer",
        help="Plan code mapped from the Apple product ID.",
    )
    parser.add_argument(
        "--apple-product-code",
        default="producer_monthly",
        help="Catalog product code mapped from the Apple product ID.",
    )
    parser.add_argument(
        "--google-plan-code",
        choices=("free", "starter", "producer", "studio", "enterprise", "education"),
        default="producer",
        help="Plan code mapped from the Google product ID.",
    )
    parser.add_argument(
        "--google-product-code",
        default="producer_monthly",
        help="Catalog product code mapped from the Google product ID.",
    )
    parser.add_argument(
        "--apple-studio-product-id",
        default="",
        help="Optional Apple product ID for a Studio plan.",
    )
    parser.add_argument(
        "--google-studio-product-id",
        default="",
        help="Optional Google product ID for a Studio plan.",
    )
    parser.add_argument(
        "--json-lines",
        action="store_true",
        help="Print one JSON object per line instead of a JSON array.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write the rows directly into DynamoDB.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    records = _build_records(args)
    if not records:
        print("No records to seed.", file=sys.stderr)
        return 1

    if args.apply:
        table_name = args.table_name or f"mixroom-catalog-mappings-{args.stage}"
        return _apply_records(table_name, records)

    if args.json_lines:
        for record in records:
            print(json.dumps(record, separators=(",", ":")))
        return 0

    print(json.dumps(records, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
