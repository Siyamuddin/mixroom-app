from __future__ import annotations

from datetime import datetime, timedelta, timezone
from html import escape as html_escape
from email.utils import parseaddr
from typing import Any, Dict, Optional
import uuid

from common.email_delivery import EmailDeliveryError, EmailSuppressedError, send_auth_email
from common.models import (
    choose_primary_subscription,
    entitlement_capabilities_for_status,
    entitlement_limits_for_status,
    free_entitlement,
    legacy_tier_for_plan_code,
    normalize_plan_code,
    normalize_provider,
    normalize_status,
    status_has_active_access,
    subscription_effective_status,
)
from common.collaboration_repository import CollaborationRepository
from common.billing_catalog_repository import BillingCatalogRepository
from common.monitoring import capture_exception, init_sentry
from common.providers import charge_toss_billing_key
from common.repository import BillingRepository
from common.secrets import load_provider_api_key

repo = BillingRepository()
collaboration_repo = CollaborationRepository()
catalog_repo = BillingCatalogRepository()
init_sentry("mixroom-app-api-reconcile")

_MOBILE_STORE_PROVIDERS = {"apple", "google"}
_MOBILE_STORE_EXPIRY_RECONCILE_GRACE = timedelta(minutes=15)
_TEAM_PLAN_CODES = {"studio", "enterprise", "education"}
_TOSS_KRW_AMOUNTS = {
    "starter_monthly": 6600,
    "starter_yearly": 77000,
    "producer_monthly": 29000,
    "producer_yearly": 299000,
    "studio_monthly": 149000,
    "studio_yearly": 1490000,
}
_TOSS_RENEWAL_GRACE = timedelta(days=3)
_DASHBOARD_URL = "https://www.mixroom.ai/dashboard"
_NOTICE_FROM_STATUSES = {"active", "trialing", "grace_period", "past_due"}
_PAYMENT_PROBLEM_STATUSES = {"grace_period", "past_due"}


def _is_team_plan(raw: Dict[str, Any]) -> bool:
    plan_code = normalize_plan_code(
        raw.get("plan_code")
        or raw.get("tier")
        or "free"
    )
    return plan_code in _TEAM_PLAN_CODES


def _personal_subscriptions(subscriptions: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return [item for item in subscriptions if not _is_team_plan(item)]


def _sync_team_organization(subscription: Dict[str, Any]) -> None:
    plan_code = str(subscription.get("plan_code") or subscription.get("tier") or "").strip().lower()
    if plan_code not in {"studio", "enterprise", "education"}:
        return
    try:
        collaboration_repo.sync_organization_for_subscription(subscription)
    except Exception as exc:
        capture_exception(
            exc,
            tags={
                "service": "subscriptions_reconcile",
                "operation": "sync_team_organization",
                "plan_code": plan_code,
            },
            context={
                "subscription_id": subscription.get("subscription_id"),
                "user_id": subscription.get("user_id"),
                "status": subscription.get("status"),
            },
        )
        return


def _parse_ts(raw: Any) -> Optional[datetime]:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def _plan_label(sub: Dict[str, Any]) -> str:
    raw = normalize_plan_code(sub.get("plan_code") or sub.get("tier") or "free")
    return {
        "free": "Free",
        "starter": "Starter",
        "producer": "Producer",
        "studio": "Studio",
        "education": "Education",
        "enterprise": "Enterprise",
    }.get(raw, raw.replace("_", " ").replace("-", " ").title())


def _date_label(value: datetime, locale: str = "en") -> str:
    if locale == "ko":
        return f"{value.year}년 {value.month}월 {value.day}일"
    return value.strftime("%b %-d, %Y") if hasattr(value, "strftime") else value.isoformat()


def _notification_locale(profile: Dict[str, Any]) -> str:
    locale = str(profile.get("locale_code") or profile.get("locale") or "").strip().lower()
    return "ko" if locale.startswith("ko") else "en"


def _recipient_email(sub: Dict[str, Any]) -> str:
    candidates: list[str] = []
    for value in (
        sub.get("customer_email"),
        sub.get("billing_email"),
        sub.get("email"),
    ):
        if value:
            candidates.append(str(value))

    user_id = str(sub.get("user_id") or "").strip()
    if user_id:
        try:
            profile = repo.get_user_profile(user_id) or {}
        except Exception:
            profile = {}
        for value in (
            profile.get("email_lc"),
            profile.get("email"),
        ):
            if value:
                candidates.append(str(value))
        try:
            account = repo.get_auth_account(user_id) or {}
        except Exception:
            account = {}
        for value in (
            account.get("email_lc"),
            account.get("email"),
        ):
            if value:
                candidates.append(str(value))

    for candidate in candidates:
        email = parseaddr(candidate)[1].strip().lower()
        if email and email == candidate.strip().lower() and "@" in email:
            return email
    return ""


def _notification_profile(sub: Dict[str, Any]) -> Dict[str, Any]:
    user_id = str(sub.get("user_id") or "").strip()
    if not user_id:
        return {}
    try:
        profile = repo.get_user_profile(user_id)
    except Exception:
        return {}
    return profile if isinstance(profile, dict) else {}


def _has_toss_billing_key(sub: Dict[str, Any]) -> bool:
    return bool(
        str(sub.get("billing_key_parameter_name") or "").strip()
        or str(sub.get("billing_key_secret_arn") or "").strip()
    )


def _should_send_ending_notice(sub: Dict[str, Any]) -> bool:
    status = normalize_status(str(sub.get("status") or ""))
    if status not in {"active", "trialing"}:
        return False
    if not _parse_ts(sub.get("expires_at")):
        return False
    if bool(sub.get("cancel_at_period_end") or False):
        return True

    provider = normalize_provider(str(sub.get("provider") or "unknown"))
    if provider == "admin_grant":
        return True
    if provider == "toss" and not _has_toss_billing_key(sub):
        return True
    if provider == "unknown" and not str(sub.get("next_billed_at") or "").strip():
        return True
    return False


def _notice_job_id(sub: Dict[str, Any], notice_type: str, date_key: str) -> str:
    subscription_id = str(sub.get("subscription_id") or "unknown").strip() or "unknown"
    return f"billing_notice#{notice_type}#{subscription_id}#{date_key}"


def _record_notice_sent_once(
    *,
    sub: Dict[str, Any],
    notice_type: str,
    date_key: str,
    recipient: str,
    now: datetime,
) -> bool:
    marker = {
        "job_id": _notice_job_id(sub, notice_type, date_key),
        "job_type": "billing_notification",
        "notice_type": notice_type,
        "subscription_id": str(sub.get("subscription_id") or ""),
        "user_id": str(sub.get("user_id") or ""),
        "recipient_email": recipient,
        "sent_at": now.isoformat(),
        "created_at": now.isoformat(),
    }
    if hasattr(repo, "record_reconciliation_job_once"):
        return bool(repo.record_reconciliation_job_once(marker))
    repo.record_reconciliation_job(marker)
    return True


def _notice_already_sent(sub: Dict[str, Any], notice_type: str, date_key: str) -> bool:
    if not hasattr(repo, "get_reconciliation_job"):
        return False
    try:
        return bool(repo.get_reconciliation_job(_notice_job_id(sub, notice_type, date_key)))
    except Exception:
        return False


def _email_copy(
    *,
    notice_type: str,
    sub: Dict[str, Any],
    ending_at: Optional[datetime],
    locale: str,
) -> tuple[str, str, str]:
    plan = _plan_label(sub)
    date = _date_label(ending_at, locale) if ending_at else ""
    if locale == "ko":
        if notice_type == "payment_problem":
            subject = "Mixroom 결제 정보를 확인해 주세요"
            intro = f"{plan} 플랜 결제가 완료되지 않았습니다."
            detail = "서비스가 중단되지 않도록 대시보드에서 결제 상태를 확인하거나 결제 수단을 업데이트해 주세요."
        elif notice_type == "payment_final":
            subject = "Mixroom 결제 최종 확인이 필요합니다"
            intro = f"{plan} 플랜 결제 문제가 아직 해결되지 않았습니다."
            detail = f"{date}까지 결제가 복구되지 않으면 유료 기능 접근이 중단될 수 있습니다."
        elif notice_type == "access_ended":
            subject = "Mixroom 플랜이 종료되었습니다"
            intro = f"{plan} 플랜 이용 기간이 종료되었습니다."
            detail = "대시보드에서 현재 접근 권한과 사용 가능한 플랜을 확인할 수 있습니다."
        else:
            subject = "Mixroom 플랜 종료 예정 안내"
            intro = f"{plan} 플랜이 {date}에 종료될 예정입니다."
            detail = "계속 사용하려면 대시보드에서 갱신 또는 플랜 변경을 확인해 주세요."
        action = "대시보드 열기"
        footer = "이미 해결했다면 이 메일은 무시하셔도 됩니다."
    else:
        if notice_type == "payment_problem":
            subject = "Action needed: update your Mixroom payment"
            intro = f"We could not complete payment for your {plan} plan."
            detail = "Please check your billing status or update your payment method from the dashboard to avoid interruption."
        elif notice_type == "payment_final":
            subject = "Final reminder: Mixroom payment needed"
            intro = f"The payment issue for your {plan} plan is still unresolved."
            detail = f"If payment is not recovered by {date}, paid access may be interrupted."
        elif notice_type == "access_ended":
            subject = "Your Mixroom plan has ended"
            intro = f"Your {plan} plan period has ended."
            detail = "You can review your current access and available plans from the dashboard."
        else:
            subject = "Your Mixroom plan is ending soon"
            intro = f"Your {plan} plan is scheduled to end on {date}."
            detail = "To keep access, review renewal or plan options from your dashboard."
        action = "Open dashboard"
        footer = "If you already handled this, you can ignore this email."

    text = "\n\n".join([intro, detail, f"{action}: {_DASHBOARD_URL}", footer])
    html = (
        "<div style=\"font-family:Inter,Arial,sans-serif;line-height:1.55;color:#111827\">"
        f"<p>{html_escape(intro)}</p>"
        f"<p>{html_escape(detail)}</p>"
        f"<p><a href=\"{_DASHBOARD_URL}\" style=\"display:inline-block;background:#1f6feb;color:#fff;"
        "padding:10px 14px;border-radius:8px;text-decoration:none;font-weight:600\">"
        f"{html_escape(action)}</a></p>"
        f"<p style=\"color:#6b7280;font-size:13px\">{html_escape(footer)}</p>"
        "</div>"
    )
    return subject, text, html


def _send_billing_notice(
    *,
    sub: Dict[str, Any],
    notice_type: str,
    date_key: str,
    now: datetime,
    ending_at: Optional[datetime] = None,
) -> bool:
    recipient = _recipient_email(sub)
    if not recipient:
        return False
    if _notice_already_sent(sub, notice_type, date_key):
        return False

    profile = _notification_profile(sub)
    locale = _notification_locale(profile)
    subject, text_body, html_body = _email_copy(
        notice_type=notice_type,
        sub=sub,
        ending_at=ending_at,
        locale=locale,
    )
    try:
        send_auth_email(
            to_email=recipient,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )
        _record_notice_sent_once(
            sub=sub,
            notice_type=notice_type,
            date_key=date_key,
            recipient=recipient,
            now=now,
        )
        return True
    except EmailSuppressedError:
        _record_notice_sent_once(
            sub=sub,
            notice_type=notice_type,
            date_key=date_key,
            recipient=recipient,
            now=now,
        )
        return False
    except EmailDeliveryError as exc:
        capture_exception(
            exc,
            tags={"service": "subscriptions_reconcile", "operation": "billing_notice"},
            context={
                "subscription_id": sub.get("subscription_id"),
                "user_id": sub.get("user_id"),
                "notice_type": notice_type,
            },
        )
        return False


def _send_subscription_notifications(now: datetime) -> int:
    sent = 0
    for sub in repo.scan_subscriptions():
        status = normalize_status(str(sub.get("status") or ""))
        if status not in _NOTICE_FROM_STATUSES:
            continue

        expires_at = _parse_ts(sub.get("expires_at"))
        date_key = expires_at.date().isoformat() if expires_at else "open"
        if status in _PAYMENT_PROBLEM_STATUSES:
            notice_type = "payment_final" if expires_at and expires_at - now <= timedelta(days=1) else "payment_problem"
            if _send_billing_notice(
                sub=sub,
                notice_type=notice_type,
                date_key=date_key,
                now=now,
                ending_at=expires_at,
            ):
                sent += 1
            continue

        if not _should_send_ending_notice(sub) or not expires_at:
            continue
        remaining = expires_at - now
        if remaining <= timedelta(0) or remaining > timedelta(days=7):
            continue
        notice_type = "ending_1d" if remaining <= timedelta(days=1) else "ending_7d"
        if _send_billing_notice(
            sub=sub,
            notice_type=notice_type,
            date_key=date_key,
            now=now,
            ending_at=expires_at,
        ):
            sent += 1
    return sent


def _send_test_billing_notifications(event: Dict[str, Any], now: datetime) -> Dict[str, Any]:
    to_email = str(event.get("to_email") or event.get("email") or "").strip().lower()
    if not to_email:
        to_email = "andrew@mixroom.ai"
    sample_sub = {
        "subscription_id": f"test-{uuid.uuid4().hex[:12]}",
        "user_id": "test",
        "provider": "admin_grant",
        "plan_code": "producer",
        "status": "active",
        "expires_at": (now + timedelta(days=7)).isoformat(),
        "customer_email": to_email,
        "cancel_at_period_end": True,
    }
    sent = 0
    for notice_type, ending_at in (
        ("ending_7d", now + timedelta(days=7)),
        ("payment_problem", now + timedelta(days=3)),
    ):
        subject, text_body, html_body = _email_copy(
            notice_type=notice_type,
            sub=sample_sub,
            ending_at=ending_at,
            locale="en",
        )
        send_auth_email(
            to_email=to_email,
            subject=f"[Test] {subject}",
            text_body=text_body,
            html_body=html_body,
        )
        sent += 1
    return {"statusCode": 200, "body": f"sent={sent}, to={to_email}"}


def _toss_amount_for_subscription(sub: Dict[str, Any]) -> int:
    try:
        amount = int(sub.get("billing_amount") or 0)
        if amount > 0:
            return amount
    except (TypeError, ValueError):
        pass
    product_code = str(sub.get("product_code") or "").strip().lower()
    product = catalog_repo.get_product(product_code) if product_code else {}
    for raw in (
        product.get("price_krw") if isinstance(product, dict) else None,
        product.get("amount_krw") if isinstance(product, dict) else None,
        _TOSS_KRW_AMOUNTS.get(product_code),
    ):
        try:
            amount = int(raw or 0)
            if amount > 0:
                return amount
        except (TypeError, ValueError):
            continue
    return 0


def _add_months(value: datetime, months: int) -> datetime:
    year = value.year + ((value.month - 1 + months) // 12)
    month = (value.month - 1 + months) % 12 + 1
    from calendar import monthrange

    day = min(value.day, monthrange(year, month)[1])
    return value.replace(year=year, month=month, day=day)


def _next_toss_billed_at(sub: Dict[str, Any], from_time: datetime) -> str:
    product_code = str(sub.get("product_code") or "").strip().lower()
    product = catalog_repo.get_product(product_code) if product_code else {}
    interval = str((product or {}).get("billing_interval") or "").strip().lower()
    if interval == "yearly" or product_code.endswith("_yearly"):
        return _add_months(from_time, 12).isoformat()
    return _add_months(from_time, 1).isoformat()


def _refresh_current_entitlement_from_subscription(sub: Dict[str, Any]) -> None:
    user_id = str(sub.get("user_id") or "").strip()
    sub_id = str(sub.get("subscription_id") or "").strip()
    entitlement = repo.get_entitlement(user_id)
    if not entitlement or str(entitlement.get("source_subscription_id") or "") != sub_id:
        return
    entitlement["status"] = subscription_effective_status(sub)
    entitlement["expires_at"] = sub.get("expires_at")
    entitlement["next_billed_at"] = sub.get("next_billed_at")
    entitlement["payment_method"] = sub.get("payment_method")
    entitlement["cancel_at_period_end"] = bool(sub.get("cancel_at_period_end") or False)
    entitlement["revision"] = int(entitlement.get("revision") or 0) + 1
    repo.put_entitlement(entitlement)


def _renew_due_toss_subscription(sub: Dict[str, Any], now: datetime) -> str:
    if str(sub.get("provider") or "").strip().lower() != "toss":
        return ""
    if bool(sub.get("cancel_at_period_end") or False):
        return ""
    next_billed_at = _parse_ts(sub.get("next_billed_at"))
    if not next_billed_at or next_billed_at > now:
        return ""
    parameter_name = str(sub.get("billing_key_parameter_name") or "").strip()
    secret_arn = str(sub.get("billing_key_secret_arn") or "").strip()
    customer_key = str(sub.get("customer_id") or "").strip()
    amount = _toss_amount_for_subscription(sub)
    if not (parameter_name or secret_arn) or not customer_key or amount <= 0:
        return ""

    billing_key = load_provider_api_key(secret_arn, parameter_name)
    order_id = f"mixroom-{uuid.uuid4().hex[:24]}"
    product_code = str(sub.get("product_code") or "Mixroom subscription").strip()
    payment = charge_toss_billing_key(
        billing_key,
        customer_key=customer_key,
        amount=amount,
        order_id=order_id,
        order_name=product_code,
        customer_email=str(sub.get("customer_email") or ""),
    )
    if str(payment.get("status") or "").strip().upper() != "DONE":
        updated = dict(sub)
        updated["status"] = "grace_period"
        updated["expires_at"] = (now + _TOSS_RENEWAL_GRACE).isoformat()
        updated["last_payment_error_at"] = now.isoformat()
        repo.upsert_subscription(updated)
        _refresh_current_entitlement_from_subscription(updated)
        return "grace"

    renewed_until = _next_toss_billed_at(sub, now)
    updated = dict(sub)
    updated["status"] = "active"
    updated["expires_at"] = renewed_until
    updated["next_billed_at"] = renewed_until
    card = payment.get("card") if isinstance(payment.get("card"), dict) else {}
    if card:
        updated["payment_method"] = {
            "brand": str(card.get("company") or card.get("issuerCode") or "").strip(),
            "last4": str(card.get("number") or "")[-4:],
        }
    repo.upsert_subscription(updated)
    _refresh_current_entitlement_from_subscription(updated)
    return "renewed"


def _subscription_iterable(now: datetime) -> list[Dict[str, Any]]:
    seen: set[str] = set()
    selected: list[Dict[str, Any]] = []

    def add(item: Dict[str, Any]) -> None:
        subscription_id = str(item.get("subscription_id") or "").strip()
        if not subscription_id or subscription_id in seen:
            return
        seen.add(subscription_id)
        selected.append(item)

    if hasattr(repo, "list_expired_subscriptions_for_statuses"):
        for sub in repo.list_expired_subscriptions_for_statuses(
            statuses=("active", "trialing", "grace_period", "past_due"),
            expires_before=now.isoformat(),
        ):
            add(sub)
    else:
        for sub in repo.scan_subscriptions():
            status = normalize_status(str(sub.get("status") or ""))
            expires_at = _parse_ts(sub.get("expires_at"))
            if status in {"active", "trialing", "grace_period", "past_due"} and expires_at and expires_at < now:
                add(sub)

    for sub in repo.scan_subscriptions():
        if str(sub.get("provider") or "").strip().lower() != "toss":
            continue
        if bool(sub.get("cancel_at_period_end") or False):
            continue
        status = normalize_status(str(sub.get("status") or ""))
        if status not in {"active", "trialing", "grace_period"}:
            continue
        next_billed_at = _parse_ts(sub.get("next_billed_at"))
        if next_billed_at and next_billed_at <= now:
            add(sub)
    return selected


def handler(_event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    now = datetime.now(timezone.utc)
    if isinstance(_event, dict) and _event.get("action") == "send_test_billing_notifications":
        return _send_test_billing_notifications(_event, now)

    scanned = 0
    downgraded = 0
    renewed = 0
    notifications_sent = 0

    for sub in _subscription_iterable(now):
        scanned += 1
        user_id = str(sub.get("user_id") or "").strip()
        sub_id = str(sub.get("subscription_id") or "").strip()
        if not user_id or not sub_id:
            continue

        try:
            renewal_result = _renew_due_toss_subscription(sub, now)
            if renewal_result == "renewed":
                renewed += 1
                continue
            if renewal_result == "grace":
                continue
        except Exception as exc:
            capture_exception(
                exc,
                tags={"service": "subscriptions_reconcile", "operation": "toss_renewal"},
                context={"subscription_id": sub_id, "user_id": user_id},
            )

        expires_at = _parse_ts(sub.get("expires_at"))
        if not expires_at or expires_at > now:
            continue
        provider = normalize_provider(str(sub.get("provider") or "unknown"))
        if (
            provider in _MOBILE_STORE_PROVIDERS
            and expires_at + _MOBILE_STORE_EXPIRY_RECONCILE_GRACE > now
        ):
            continue

        status = str(sub.get("status") or "").lower()
        if status in {"expired", "refunded", "revoked"}:
            continue

        updated_sub = dict(sub)
        updated_sub["status"] = "expired"
        repo.upsert_subscription(updated_sub)
        _sync_team_organization(updated_sub)
        if _send_billing_notice(
            sub=updated_sub,
            notice_type="access_ended",
            date_key=expires_at.date().isoformat(),
            now=now,
            ending_at=expires_at,
        ):
            notifications_sent += 1

        current_ent = repo.get_entitlement(user_id)
        if not current_ent:
            continue

        if str(current_ent.get("source_subscription_id") or "") != sub_id:
            continue

        revision = int(current_ent.get("revision") or 0) + 1
        primary_subscription = choose_primary_subscription(
            _personal_subscriptions(repo.list_subscriptions_for_user(user_id))
        )
        if primary_subscription and status_has_active_access(
            subscription_effective_status(primary_subscription)
        ):
            selected_status = subscription_effective_status(primary_subscription)
            selected_plan_code = normalize_plan_code(
                primary_subscription.get("plan_code")
                or primary_subscription.get("tier")
                or "free"
            )
            repo.put_entitlement(
                {
                    "user_id": user_id,
                    "tier": legacy_tier_for_plan_code(selected_plan_code),
                    "status": selected_status,
                    "effective_at": primary_subscription.get("effective_at"),
                    "expires_at": primary_subscription.get("expires_at"),
                    "source_provider": normalize_provider(
                        str(primary_subscription.get("provider") or "unknown")
                    ),
                    "source_subscription_id": str(
                        primary_subscription.get("subscription_id") or ""
                    ),
                    "capabilities": entitlement_capabilities_for_status(
                        selected_plan_code,
                        selected_status,
                    ),
                    "limits": entitlement_limits_for_status(
                        selected_plan_code,
                        selected_status,
                    ),
                    "management_channel": primary_subscription.get("management_channel")
                    or primary_subscription.get("provider")
                    or "unknown",
                    "plan_code": selected_plan_code,
                    "product_code": primary_subscription.get("product_code"),
                    "source_occurred_at": primary_subscription.get("source_occurred_at"),
                    "revision": revision,
                }
            )
        else:
            free = free_entitlement(
                user_id=user_id,
                revision=revision,
            ).to_dict()
            repo.put_entitlement(free)
        downgraded += 1

    notifications_sent += _send_subscription_notifications(now)

    repo.record_reconciliation_job(
        {
            "job_id": str(uuid.uuid4()),
            "job_type": "subscription_reconcile",
            "scanned": scanned,
            "downgraded": downgraded,
            "renewed": renewed,
            "notifications_sent": notifications_sent,
            "finished_at": datetime.now(timezone.utc).isoformat(),
        }
    )

    return {
        "statusCode": 200,
        "body": (
            f"scanned={scanned}, renewed={renewed}, downgraded={downgraded}, "
            f"notifications_sent={notifications_sent}"
        ),
    }
