#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _script_env import prime_runtime_env


def _resolve_allowlist_table_name(args: argparse.Namespace) -> str:
    if args.table_name:
        return args.table_name
    if os.environ.get("ADMIN_ALLOWLIST_TABLE"):
        return str(os.environ["ADMIN_ALLOWLIST_TABLE"]).strip()
    return f"mixroom-admin-allowlist-{args.stage}"


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Allowlist an employee email and provision the Cognito account used by the admin site."
        ),
    )
    parser.add_argument("--email", required=True, help="Employee email address.")
    parser.add_argument(
        "--stage",
        default="prod",
        help="Stage suffix used when deriving the allowlist table name.",
    )
    parser.add_argument(
        "--table-name",
        default="",
        help="Override the DynamoDB allowlist table name instead of deriving it from --stage.",
    )
    parser.add_argument(
        "--user-pool-id",
        default=os.environ.get("COGNITO_USER_POOL_ID", ""),
        help="Cognito user pool ID for employee accounts.",
    )
    parser.add_argument(
        "--region",
        default=(
            os.environ.get("AWS_REGION")
            or os.environ.get("AWS_DEFAULT_REGION")
            or os.environ.get("COGNITO_REGION", "")
        ),
        help="AWS region for the Cognito user pool.",
    )
    parser.add_argument(
        "--invited-by",
        default="",
        help="Optional approver or operator email stored in the allowlist entry.",
    )
    parser.add_argument(
        "--note",
        default="",
        help="Optional note stored with the allowlist entry.",
    )
    parser.add_argument(
        "--resend",
        action="store_true",
        help="Resend the Cognito invitation email when the employee already exists.",
    )
    parser.add_argument(
        "--suppress-email",
        action="store_true",
        help="Create or update the account without sending a Cognito invitation email.",
    )
    return parser.parse_args()


def _upsert_cognito_user(args: argparse.Namespace, *, email: str) -> str:
    try:
        import boto3
    except ModuleNotFoundError:
        raise SystemExit("boto3 is required to provision Cognito employee accounts.")

    client_kwargs = {}
    if args.region:
        client_kwargs["region_name"] = args.region
    client = boto3.client("cognito-idp", **client_kwargs)

    user_attributes = [
        {"Name": "email", "Value": email},
        {"Name": "email_verified", "Value": "true"},
    ]
    create_kwargs = {
        "UserPoolId": args.user_pool_id,
        "Username": email,
        "UserAttributes": user_attributes,
        "DesiredDeliveryMediums": ["EMAIL"],
        "ForceAliasCreation": False,
    }
    if args.suppress_email:
        create_kwargs["MessageAction"] = "SUPPRESS"

    try:
        client.admin_create_user(**create_kwargs)
        return "created"
    except client.exceptions.UsernameExistsException:
        client.admin_update_user_attributes(
            UserPoolId=args.user_pool_id,
            Username=email,
            UserAttributes=user_attributes,
        )
        if args.resend and not args.suppress_email:
            client.admin_create_user(
                UserPoolId=args.user_pool_id,
                Username=email,
                DesiredDeliveryMediums=["EMAIL"],
                MessageAction="RESEND",
            )
            return "resent"
        return "existing"


def main() -> int:
    args = _parse_args()
    if not args.user_pool_id:
        raise SystemExit("--user-pool-id or COGNITO_USER_POOL_ID is required.")

    prime_runtime_env()
    os.environ["ADMIN_ALLOWLIST_TABLE"] = _resolve_allowlist_table_name(args)

    from src.common.admin_access_repository import AdminAccessRepository, normalize_email

    email = normalize_email(args.email)
    if not email:
        raise SystemExit("A valid email address is required.")

    repo = AdminAccessRepository()
    allowlist_entry = repo.put_allowlist_entry(
        email=email,
        invited_by=args.invited_by,
        note=args.note,
        access_enabled=True,
    )
    cognito_state = _upsert_cognito_user(args, email=email)

    print(f"allowlist: {allowlist_entry['email']} -> enabled ({os.environ['ADMIN_ALLOWLIST_TABLE']})")
    print(f"cognito: {email} -> {cognito_state} ({args.user_pool_id})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
