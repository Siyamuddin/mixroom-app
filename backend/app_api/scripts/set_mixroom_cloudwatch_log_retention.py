from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass


DEFAULT_REGION = "ap-northeast-2"
DEFAULT_STAGE = "prod"
SUPPORTED_RETENTION_DAYS = {
    1,
    3,
    5,
    7,
    14,
    30,
    60,
    90,
    120,
    150,
    180,
    365,
    400,
    545,
    731,
    1096,
    1827,
    2192,
    2557,
    2922,
    3288,
    3653,
}


@dataclass(frozen=True)
class LogGroup:
    name: str
    retention_in_days: int | None


def _run_aws(*args: str) -> str:
    command = ["aws", *args]
    try:
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("aws CLI is required to manage CloudWatch log retention") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        raise SystemExit(stderr or f"aws command failed: {' '.join(command)}") from exc
    return completed.stdout


def _list_log_groups(*, region: str, stage: str, include_app_api: bool, include_llm_proxy: bool) -> list[LogGroup]:
    prefixes: list[str] = []
    if include_app_api:
        prefixes.append(f"/aws/lambda/mixroom-app-api-{stage}-")
    if include_llm_proxy:
        prefixes.append(f"/aws/lambda/mixroom-llm-proxy-{stage}-")

    log_groups: list[LogGroup] = []
    for prefix in prefixes:
        raw = _run_aws(
            "logs",
            "describe-log-groups",
            "--region",
            region,
            "--log-group-name-prefix",
            prefix,
            "--query",
            "logGroups[].{name:logGroupName,retention:retentionInDays}",
            "--output",
            "json",
        )
        decoded = json.loads(raw)
        for item in decoded:
            log_groups.append(
                LogGroup(
                    name=str(item.get("name") or ""),
                    retention_in_days=item.get("retention"),
                )
            )
    return sorted(
        {group.name: group for group in log_groups if group.name}.values(),
        key=lambda group: group.name,
    )


def _set_retention(*, region: str, log_group_name: str, retention_in_days: int) -> None:
    _run_aws(
        "logs",
        "put-retention-policy",
        "--region",
        region,
        "--log-group-name",
        log_group_name,
        "--retention-in-days",
        str(retention_in_days),
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Set retention on existing Mixroom Lambda CloudWatch log groups. "
            "This is safe for app behavior and avoids trying to import auto-created log groups into CloudFormation."
        )
    )
    parser.add_argument(
        "--region",
        default=DEFAULT_REGION,
        help=f"AWS region to target. Defaults to {DEFAULT_REGION}.",
    )
    parser.add_argument(
        "--stage",
        default=DEFAULT_STAGE,
        help=f"Deployment stage suffix to target. Defaults to {DEFAULT_STAGE}.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=14,
        help="Retention window in days. Defaults to 14.",
    )
    parser.add_argument(
        "--service",
        choices=("all", "app_api", "llm_proxy"),
        default="all",
        help="Which backend log groups to update. Defaults to all.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show the intended retention changes without modifying CloudWatch.",
    )
    args = parser.parse_args()

    if args.days not in SUPPORTED_RETENTION_DAYS:
        supported = ", ".join(str(day) for day in sorted(SUPPORTED_RETENTION_DAYS))
        raise SystemExit(f"unsupported retention period {args.days}; choose one of: {supported}")

    include_app_api = args.service in {"all", "app_api"}
    include_llm_proxy = args.service in {"all", "llm_proxy"}
    log_groups = _list_log_groups(
        region=args.region,
        stage=args.stage,
        include_app_api=include_app_api,
        include_llm_proxy=include_llm_proxy,
    )
    if not log_groups:
        print(
            f"no Mixroom Lambda log groups found for stage={args.stage!r} region={args.region!r}",
            file=sys.stderr,
        )
        return 1

    changed = 0
    for group in log_groups:
        current = group.retention_in_days
        if current == args.days:
            print(f"[skip] {group.name}: already {args.days} days")
            continue
        if args.dry_run:
            print(
                f"[dry-run] {group.name}: "
                f"{current if current is not None else 'never expire'} -> {args.days} days"
            )
            changed += 1
            continue
        _set_retention(
            region=args.region,
            log_group_name=group.name,
            retention_in_days=args.days,
        )
        print(
            f"[updated] {group.name}: "
            f"{current if current is not None else 'never expire'} -> {args.days} days"
        )
        changed += 1

    if args.dry_run:
        print(f"[dry-run] {changed} log group(s) would change")
    else:
        print(f"[done] updated {changed} log group(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
