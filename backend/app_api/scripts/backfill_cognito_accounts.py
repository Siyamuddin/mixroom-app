from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Backfill a small set of app-user Cognito accounts into native auth tables.",
    )
    parser.add_argument(
        "--email",
        action="append",
        dest="emails",
        required=True,
        help="App-user email address to backfill. Pass once per account.",
    )
    args = parser.parse_args()

    try:
        from common.cognito_legacy_auth import find_user_by_email  # noqa: E402
        from common.native_auth import _migrate_legacy_cognito_account  # noqa: E402, SLF001
        from common.repository import BillingRepository  # noqa: E402
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "Missing runtime dependency for AWS backfill. Install backend app API dependencies first."
        ) from exc

    repo = BillingRepository()
    migrated: list[dict] = []
    for raw_email in args.emails:
        safe_email = str(raw_email or "").strip().lower()
        if not safe_email:
            continue
        legacy_user = find_user_by_email(safe_email)
        if not legacy_user:
            raise SystemExit(f"Could not find Cognito app user for {safe_email}.")
        result = _migrate_legacy_cognito_account(  # noqa: SLF001
            repo,
            claims=legacy_user,
            password="",
            allow_passwordless_email=True,
        )
        migrated.append(
            {
                "email": safe_email,
                "user_id": result["account"]["user_id"],
                "provider": result["account"]["auth_provider"],
                "email_verified": result["account"]["email_verified"],
            }
        )

    print(json.dumps({"migrated": migrated}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
