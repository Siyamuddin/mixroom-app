from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _script_env import prime_runtime_env


def _resolve_table_name(args: argparse.Namespace) -> str:
    if args.table_name:
        return args.table_name
    if os.environ.get("ADMIN_ALLOWLIST_TABLE"):
        return str(os.environ["ADMIN_ALLOWLIST_TABLE"]).strip()
    return f"mixroom-admin-allowlist-{args.stage}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Add or update an allowlisted employee email for the admin dashboard.",
    )
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
    parser.add_argument("--email", required=True, help="Employee email to allowlist.")
    parser.add_argument(
        "--invited-by",
        default="",
        help="Optional note for who approved the access.",
    )
    parser.add_argument(
        "--note",
        default="",
        help="Optional note stored alongside the allowlist entry.",
    )
    parser.add_argument(
        "--disable",
        action="store_true",
        help="Disable an existing entry instead of enabling it.",
    )
    args = parser.parse_args()

    prime_runtime_env()
    os.environ["ADMIN_ALLOWLIST_TABLE"] = _resolve_table_name(args)

    from src.common.admin_access_repository import AdminAccessRepository

    repo = AdminAccessRepository()
    entry = repo.put_allowlist_entry(
        email=args.email,
        invited_by=args.invited_by,
        note=args.note,
        access_enabled=not args.disable,
    )

    state = "disabled" if args.disable else "enabled"
    print(f"{entry['email']} -> {state} ({os.environ['ADMIN_ALLOWLIST_TABLE']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
