from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common.models import (  # noqa: E402
    PLAN_CODES,
    default_capabilities_for_plan,
    normalize_plan_code,
)


_PLAN_METADATA = {
    "free": ("Free", "individual"),
    "starter": ("Starter", "individual"),
    "producer": ("Producer", "individual"),
    "studio": ("Studio", "team"),
    "enterprise": ("Enterprise", "enterprise"),
    "education": ("Education", "education"),
}

_TEAM_PLAN_DEFAULTS = {
    "studio": {
        "organization_name": "Andrew Test Studio",
        "seat_limit": 5,
        "workspace_name": "Andrew Test Studio Workspace",
        "membership_role": "owner",
        "shared_workspace_enabled": True,
        "visibility": "organization",
        "default_project_privacy": "workspace",
    },
    "enterprise": {
        "organization_name": "Andrew Test Enterprise",
        "seat_limit": 500,
        "workspace_name": "Andrew Test Enterprise Workspace",
        "membership_role": "owner",
        "shared_workspace_enabled": True,
        "visibility": "organization",
        "default_project_privacy": "workspace",
    },
    "education": {
        "organization_name": "Andrew Test Academy",
        "seat_limit": 20,
        "workspace_name": "Andrew Test Academy Classroom",
        "membership_role": "teacher",
        "shared_workspace_enabled": True,
        "visibility": "organization",
        "default_project_privacy": "workspace",
    },
}


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _table_name(kind: str, stage: str) -> str:
    names = {
        "users": f"mixroom-users-{stage}",
        "username_claims": f"mixroom-user-username-claims-{stage}",
        "entitlements": f"mixroom-entitlements-current-{stage}",
        "subscriptions": f"mixroom-subscriptions-{stage}",
        "collaboration": f"mixroom-collaboration-{stage}",
    }
    try:
        return names[kind]
    except KeyError as exc:
        raise ValueError(f"Unknown table kind: {kind}") from exc


def _ddb_serialize(value: Any) -> dict[str, Any]:
    if value is None:
        return {"NULL": True}
    if isinstance(value, bool):
        return {"BOOL": value}
    if isinstance(value, int):
        return {"N": str(value)}
    if isinstance(value, float):
        return {"N": str(value)}
    if isinstance(value, list):
        return {"L": [_ddb_serialize(item) for item in value]}
    if isinstance(value, dict):
        return {"M": {str(key): _ddb_serialize(item) for key, item in value.items()}}
    return {"S": str(value)}


def _ddb_deserialize(value: Any) -> Any:
    if not isinstance(value, dict) or not value:
        return None
    if "S" in value:
        return value["S"]
    if "N" in value:
        raw = value["N"]
        try:
            return int(raw)
        except (TypeError, ValueError):
            return float(raw)
    if "BOOL" in value:
        return bool(value["BOOL"])
    if "NULL" in value:
        return None
    if "L" in value:
        return [_ddb_deserialize(item) for item in value["L"]]
    if "M" in value:
        return {key: _ddb_deserialize(item) for key, item in value["M"].items()}
    return None


def _deserialize_item(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    return {key: _ddb_deserialize(value) for key, value in raw.items()}


class DynamoClient:
    def get_item(self, table_name: str, key: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def put_item(self, table_name: str, item: dict[str, Any]) -> None:
        raise NotImplementedError


class BotoDynamoClient(DynamoClient):
    def __init__(self, *, region: str, profile: str) -> None:
        import boto3

        session_kwargs: dict[str, Any] = {"region_name": region}
        if profile:
            session_kwargs["profile_name"] = profile
        self._ddb = boto3.Session(**session_kwargs).resource("dynamodb")

    def get_item(self, table_name: str, key: dict[str, Any]) -> dict[str, Any]:
        return self._ddb.Table(table_name).get_item(Key=key).get("Item") or {}

    def put_item(self, table_name: str, item: dict[str, Any]) -> None:
        self._ddb.Table(table_name).put_item(Item=item)


class AwsCliDynamoClient(DynamoClient):
    def __init__(self, *, region: str, profile: str) -> None:
        self._region = region
        self._profile = profile

    def _run(self, args: list[str]) -> dict[str, Any]:
        command = ["aws", *args, "--region", self._region, "--output", "json"]
        if self._profile:
            command.extend(["--profile", self._profile])
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError((result.stderr or result.stdout).strip())
        if not result.stdout.strip():
            return {}
        return json.loads(result.stdout)

    def get_item(self, table_name: str, key: dict[str, Any]) -> dict[str, Any]:
        payload = self._run(
            [
                "dynamodb",
                "get-item",
                "--table-name",
                table_name,
                "--key",
                json.dumps({name: _ddb_serialize(value) for name, value in key.items()}),
            ]
        )
        return _deserialize_item(payload.get("Item"))

    def put_item(self, table_name: str, item: dict[str, Any]) -> None:
        self._run(
            [
                "dynamodb",
                "put-item",
                "--table-name",
                table_name,
                "--item",
                json.dumps({name: _ddb_serialize(value) for name, value in item.items()}),
            ]
        )


def _create_dynamo_client(*, region: str, profile: str) -> DynamoClient:
    try:
        import boto3  # noqa: F401
    except ModuleNotFoundError:
        return AwsCliDynamoClient(region=region, profile=profile)
    return BotoDynamoClient(region=region, profile=profile)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Switch one test account between Mixroom plans and create the team-plan "
            "organization records needed for local app testing."
        ),
    )
    parser.add_argument("--username", required=True, help="App username, e.g. andrew_leew.")
    parser.add_argument("--plan-code", required=True, choices=PLAN_CODES)
    parser.add_argument("--stage", required=True, help="Deployment stage, e.g. prod.")
    parser.add_argument("--region", default="ap-northeast-2")
    parser.add_argument("--profile", default="")
    parser.add_argument("--organization-id", default="")
    parser.add_argument("--organization-name", default="")
    parser.add_argument("--seat-limit", type=int, default=0)
    parser.add_argument("--workspace-id", default="")
    parser.add_argument("--workspace-name", default="")
    parser.add_argument(
        "--personal-only",
        action="store_true",
        help="Only write entitlement/subscription rows; skip org/workspace rows.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually write DynamoDB rows. Without this, the script prints a dry-run plan.",
    )
    return parser.parse_args()


def _resolve_user(ddb: DynamoClient, *, username: str, stage: str) -> dict[str, Any]:
    username_lc = username.strip().lower()
    claim = ddb.get_item(_table_name("username_claims", stage), {"username_lc": username_lc})
    user_id = _safe_str(claim.get("user_id"))
    if not user_id:
        raise SystemExit(f"Username not found in username claims: {username_lc}")

    profile = ddb.get_item(_table_name("users", stage), {"user_id": user_id})
    return {
        "user_id": user_id,
        "username": _safe_str(profile.get("username") or username),
        "email": _safe_str(profile.get("email") or profile.get("email_lc")).lower(),
        "profile": profile,
    }


def _build_entitlement(
    *,
    user_id: str,
    plan_code: str,
    existing: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    entitlement_plan_code = plan_code
    if plan_code in _TEAM_PLAN_DEFAULTS:
        existing_plan_code = normalize_plan_code(existing.get("plan_code") or "free")
        entitlement_plan_code = (
            existing_plan_code
            if existing_plan_code not in _TEAM_PLAN_DEFAULTS
            else "free"
        )
    label, group = _PLAN_METADATA[entitlement_plan_code]
    revision = int(existing.get("revision") or 0) + 1
    subscription_id = (
        "free-default"
        if entitlement_plan_code == "free"
        else f"test_admin:{user_id}:{entitlement_plan_code}"
    )
    return {
        "user_id": user_id,
        "status": "active",
        "effective_at": now,
        "expires_at": None,
        "source_provider": "admin_grant",
        "source_subscription_id": subscription_id,
        "capabilities": default_capabilities_for_plan(entitlement_plan_code),
        "management_channel": "admin" if entitlement_plan_code != "free" else "free",
        "revision": revision,
        "plan_code": entitlement_plan_code,
        "plan_label": label,
        "plan_group": group,
        "updated_at": now,
        "status_key": "active",
        "tier_key": entitlement_plan_code,
    }


def _build_subscription(*, user_id: str, plan_code: str, now: str) -> dict[str, Any] | None:
    if plan_code == "free":
        return None
    return {
        "subscription_id": f"test_admin:{user_id}:{plan_code}",
        "user_id": user_id,
        "provider": "admin_grant",
        "plan_code": plan_code,
        "status": "active",
        "effective_at": now,
        "product_id": "",
        "product_code": f"{plan_code}_test_admin",
        "management_channel": "admin",
        "source_event_id": "",
        "source_occurred_at": now,
        "updated_at": now,
        "status_key": "active",
    }


def _team_records(
    *,
    user_id: str,
    email: str,
    plan_code: str,
    now: str,
    args: argparse.Namespace,
) -> list[dict[str, Any]]:
    records = _inactive_test_team_records(
        user_id=user_id,
        now=now,
        active_plan_code="" if args.personal_only else plan_code,
    )
    if plan_code not in _TEAM_PLAN_DEFAULTS or args.personal_only:
        return records

    defaults = _TEAM_PLAN_DEFAULTS[plan_code]
    organization_id = (
        _safe_str(args.organization_id) or f"test-{plan_code}-{user_id.replace(':', '-').lower()}"
    )
    workspace_id = _safe_str(args.workspace_id) or f"{organization_id}-workspace"
    organization_name = _safe_str(args.organization_name) or defaults["organization_name"]
    workspace_name = _safe_str(args.workspace_name) or defaults["workspace_name"]
    seat_limit = args.seat_limit if args.seat_limit > 0 else int(defaults["seat_limit"])
    role = str(defaults["membership_role"])

    organization = {
        "entity_id": f"organization#{organization_id}",
        "entity_type": "organization",
        "organization_id": organization_id,
        "name": organization_name,
        "status": "active",
        "plan_code": plan_code,
        "seat_limit": seat_limit,
        "seat_options": [10, 20, 30] if plan_code == "education" else [],
        "education_admin_enabled": plan_code == "education",
        "teacher_mode_enabled": plan_code == "education",
        "shared_workspace_enabled": bool(defaults["shared_workspace_enabled"]),
        "support_notes": "Created by switch_test_team_plan.py for local tier testing.",
        "created_at": now,
        "updated_at": now,
        "updated_by_user_id": "local-test-script",
        "updated_by_email": "",
    }
    membership = {
        "entity_id": f"membership#{organization_id}:{user_id}",
        "entity_type": "membership",
        "organization_id": organization_id,
        "user_id": user_id,
        "email": email,
        "role": role,
        "status": "active",
        "seat_consumed": False if plan_code == "education" and role == "teacher" else True,
        "invite_token": "",
        "invite_url": "",
        "app_invite_url": "",
        "invited_at": "",
        "activated_at": now,
        "released_at": "",
        "created_at": now,
        "updated_at": now,
        "updated_by_user_id": "local-test-script",
        "updated_by_email": "",
    }
    workspace = {
        "entity_id": f"workspace#{workspace_id}",
        "entity_type": "workspace",
        "workspace_id": workspace_id,
        "organization_id": organization_id,
        "user_id": user_id,
        "name": workspace_name,
        "status": "active",
        "visibility": defaults["visibility"],
        "default_project_privacy": defaults["default_project_privacy"],
        "created_at": now,
        "updated_at": now,
        "updated_by_user_id": "local-test-script",
        "updated_by_email": "",
    }
    records.extend([organization, membership, workspace])
    return records


def _inactive_test_team_records(
    *,
    user_id: str,
    now: str,
    active_plan_code: str,
) -> list[dict[str, Any]]:
    normalized_user_id = user_id.replace(":", "-").lower()
    records: list[dict[str, Any]] = []
    for plan_code in _TEAM_PLAN_DEFAULTS:
        if plan_code == active_plan_code:
            continue
        organization_id = f"test-{plan_code}-{normalized_user_id}"
        workspace_id = f"{organization_id}-workspace"
        records.extend(
            [
                {
                    "entity_id": f"membership#{organization_id}:{user_id}",
                    "entity_type": "membership",
                    "organization_id": organization_id,
                    "user_id": user_id,
                    "email": "",
                    "role": "member",
                    "status": "inactive",
                    "seat_consumed": False,
                    "invite_token": "",
                    "invite_url": "",
                    "app_invite_url": "",
                    "invited_at": "",
                    "activated_at": "",
                    "released_at": now,
                    "created_at": now,
                    "updated_at": now,
                    "updated_by_user_id": "local-test-script",
                    "updated_by_email": "",
                },
                {
                    "entity_id": f"organization#{organization_id}",
                    "entity_type": "organization",
                    "organization_id": organization_id,
                    "name": f"Inactive {plan_code.title()} Test Org",
                    "status": "archived",
                    "plan_code": plan_code,
                    "seat_limit": 0,
                    "seat_options": [10, 20, 30] if plan_code == "education" else [],
                    "education_admin_enabled": False,
                    "teacher_mode_enabled": False,
                    "shared_workspace_enabled": False,
                    "support_notes": "Deactivated by switch_test_team_plan.py.",
                    "created_at": now,
                    "updated_at": now,
                    "updated_by_user_id": "local-test-script",
                    "updated_by_email": "",
                },
                {
                    "entity_id": f"workspace#{workspace_id}",
                    "entity_type": "workspace",
                    "workspace_id": workspace_id,
                    "organization_id": organization_id,
                    "user_id": user_id,
                    "name": f"Inactive {plan_code.title()} Test Workspace",
                    "status": "archived",
                    "visibility": "private",
                    "default_project_privacy": "private",
                    "created_at": now,
                    "updated_at": now,
                    "updated_by_user_id": "local-test-script",
                    "updated_by_email": "",
                },
            ]
        )
    return records


def main() -> int:
    args = _parse_args()
    plan_code = normalize_plan_code(args.plan_code)
    if plan_code not in PLAN_CODES:
        raise SystemExit(f"--plan-code must be one of: {', '.join(PLAN_CODES)}")

    ddb = _create_dynamo_client(region=args.region, profile=args.profile)

    user = _resolve_user(ddb, username=args.username, stage=args.stage)
    user_id = user["user_id"]
    now = _utc_now_iso()
    existing_entitlement = ddb.get_item(
        _table_name("entitlements", args.stage),
        {"user_id": user_id},
    )
    entitlement = _build_entitlement(
        user_id=user_id,
        plan_code=plan_code,
        existing=existing_entitlement,
        now=now,
    )
    subscription = _build_subscription(user_id=user_id, plan_code=plan_code, now=now)
    team_records = _team_records(
        user_id=user_id,
        email=user["email"],
        plan_code=plan_code,
        now=now,
        args=args,
    )

    output = {
        "dry_run": not args.apply,
        "stage": args.stage,
        "region": args.region,
        "username": user["username"],
        "user_id": user_id,
        "email": user["email"],
        "plan_code": plan_code,
        "writes": {
            "entitlement": entitlement,
            "subscription": subscription,
            "team_records": team_records,
        },
    }

    if not args.apply:
        print(json.dumps(output, indent=2, default=str))
        return 0

    ddb.put_item(_table_name("entitlements", args.stage), entitlement)
    if subscription is not None:
        ddb.put_item(_table_name("subscriptions", args.stage), subscription)
    for record in team_records:
        ddb.put_item(_table_name("collaboration", args.stage), record)

    print(json.dumps(output, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
