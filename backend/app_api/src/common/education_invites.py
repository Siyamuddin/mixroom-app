from __future__ import annotations

import re
from html import escape
from typing import Any, Dict
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from .access_period import access_period_active, normalize_access_expiry, earliest_access_expiry, parse_access_expiry
from .email_delivery import EmailDeliveryError, EmailSuppressedError, send_auth_email


def _education_invite_email_locale(locale):
    return "ko" if str(locale or "").lower().startswith("ko") else "en"


def _url_with_query_param(url: str, key: str, value: str) -> str:
    safe_url = str(url or "").strip()
    safe_key = str(key or "").strip()
    safe_value = str(value or "").strip()
    if not safe_url or not safe_key or not safe_value:
        return safe_url
    parts = urlsplit(safe_url)
    query = [
        (existing_key, existing_value)
        for existing_key, existing_value in parse_qsl(parts.query, keep_blank_values=True)
        if existing_key != safe_key
    ]
    query.append((safe_key, safe_value))
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment)
    )

def send_education_invite_email(
    *,
    membership: Dict[str, Any],
    organization: Dict[str, Any],
    locale: str = "",
    send_email=send_auth_email,
) -> tuple[bool, str]:
    email = str(membership.get("email") or "").strip().lower()
    email_locale = _education_invite_email_locale(locale)
    invite_url = _url_with_query_param(
        str(membership.get("invite_url") or "").strip(),
        "lang",
        email_locale,
    )
    invite_code = str(membership.get("invite_token") or "").strip()
    if not invite_code:
        parts = urlsplit(invite_url)
        invite_code = dict(parse_qsl(parts.query)).get("invite", "").strip()
        if not invite_code:
            path = parts.path.strip("/").split("/")
            if "invites" in path and path.index("invites") + 1 < len(path):
                invite_code = path[path.index("invites") + 1]
    if not email or not invite_url or not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", invite_code):
        return False, "missing_invite_email_or_url"
    app_invite_url = f"mixroom://education/invites/{invite_code}"
    organization_name = str(organization.get("name") or "Mixroom Education").strip()
    safe_org = escape(organization_name)
    safe_url = escape(invite_url, quote=True)
    safe_app_url = escape(app_invite_url, quote=True)
    safe_code = escape(invite_code)
    teacher = membership.get("role") == "teacher"
    if email_locale == "ko":
        subject = f"{organization_name} Mixroom {'교사' if teacher else '학생'} 초대"
        intro = f"{organization_name}의 {'교사' if teacher else '학생'}로 초대되었습니다."
        instructions = f"Mixroom에서 {email} 주소로 가입하거나 로그인한 후 초대를 수락하세요."
        open_label = "Mixroom 앱에서 열기"
        code_label = "초대 코드"
        fallback = "앱이 열리지 않으면 Mixroom의 계정 → 구독 → 교육 초대에 아래 코드를 붙여넣고 수락하세요."
        web_label = "웹에서 가입 또는 로그인"
        ignore = "예상하지 못한 초대라면 이 이메일을 무시해 주세요."
    else:
        subject = f"Your {'teacher' if teacher else 'student'} invitation to {organization_name} on Mixroom"
        intro = f"You are invited as a {'teacher' if teacher else 'student'} at {organization_name}."
        instructions = f"Create a Mixroom account or sign in with {email}, then accept this invitation."
        open_label = "Open in Mixroom"
        code_label = "Invitation code"
        fallback = "If the app does not open, go to Account → Subscription → Education invite in Mixroom, paste this code, and select Accept."
        web_label = "Sign up or sign in on the website"
        ignore = "If you were not expecting this invitation, you can ignore it."
    text_body = (
        f"{intro}\n\n{instructions}\n\n{open_label}:\n{app_invite_url}\n\n"
        f"{code_label}:\n{invite_code}\n\n{fallback}\n\n{web_label}:\n{invite_url}\n\n{ignore}\n"
    )
    html_body = (
        f"<p>{escape(intro)}</p><p>{escape(instructions)}</p>"
        f'<p><a href="{safe_app_url}">{open_label}</a></p>'
        f"<p><strong>{code_label}</strong></p>"
        f'<p><code style="font-size:18px;user-select:all;word-break:break-all">{safe_code}</code></p>'
        f"<p>{escape(fallback)}</p>"
        f'<p><a href="{safe_url}">{web_label}</a></p><p>{ignore}</p>'
    )
    expiry = earliest_access_expiry(membership, organization)
    if expiry:
        label = "교육 이용 종료 (UTC)" if email_locale == "ko" else "Education access ends (UTC)"
        readable = parse_access_expiry(expiry).strftime("%Y-%m-%d %H:%M")
        text_body += f"\n{label}: {readable}\n"
        html_body += f"<p>{label}: {readable}</p>"
    try:
        send_email(
            to_email=email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )
        return True, ""
    except EmailSuppressedError:
        return False, "suppressed"
    except EmailDeliveryError:
        return False, "delivery_failed"


def review_education_roster(repository, organization_id, emails, access_expires_at=""):
    organization = repository.get_organization(organization_id)
    if not organization or organization.get("plan_code") != "education":
        raise ValueError("Select an Education organization.")
    if not access_period_active(organization):
        raise ValueError("This class has ended. Extend the organization's access period before inviting students.")
    access_expires_at = normalize_access_expiry(access_expires_at)
    if access_expires_at and organization.get("access_expires_at") and parse_access_expiry(access_expires_at) > parse_access_expiry(organization["access_expires_at"]):
        raise ValueError("Student access cannot end after the class end date.")
    if organization.get("status") != "active":
        raise ValueError("Activate this Education organization before inviting students.")
    if not isinstance(emails, list) or not 1 <= len(emails) <= 500:
        raise ValueError("Review between 1 and 500 email addresses at a time.")
    members = repository.list_memberships(organization_id=organization_id)
    reserved = {}
    for member in members:
        if member.get("status") in {"active", "pending"} and access_period_active(member):
            email = str(member.get("email") or "").strip().lower()
            if email not in reserved or member.get("status") == "active":
                reserved[email] = member
    rows, seen = [], set()
    duplicates = 0
    for value in emails:
        email = str(value or "").strip().lower()
        if email in seen:
            duplicates += 1
            continue
        seen.add(email)
        row = {"email": email, "status": "ready"}
        if len(email) > 254 or not re.fullmatch(r"[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+", email):
            row["status"] = "invalid"
        elif email in reserved:
            member = reserved[email]
            row["access_expires_at"] = earliest_access_expiry(member, organization)
            row["status"] = "already_active" if member.get("status") == "active" else "pending"
            if member.get("role") != "student":
                row["status"] = "existing_staff"
            elif row["status"] == "pending":
                row["invite_url"] = member.get("invite_url", "")
        rows.append(row)
    needed = sum(row["status"] == "ready" for row in rows)
    available = max(int(organization.get("seats_available") or 0), 0)
    return {"organization": organization, "access_expires_at": earliest_access_expiry(organization, {"access_expires_at": access_expires_at}), "rows": rows, "duplicates": duplicates,
            "seats_needed": needed, "seats_available": available,
            "can_send": needed > 0 and needed <= available and all(row["status"] != "invalid" for row in rows)}


def invite_education_student(repository, body, *, admin_user_id, admin_email):
    organization_id = str(body.get("organization_id") or "").strip()
    review = review_education_roster(repository, organization_id, [body.get("email")])
    row = review["rows"][0]
    if row["status"] == "invalid":
        raise ValueError("Enter a valid student email address.")
    if row["status"] in {"already_active", "existing_staff"}:
        return row
    resend = body.get("resend") is True
    if row["status"] == "pending" and not resend:
        return row
    if row["status"] == "pending":
        membership = next(member for member in repository.list_memberships(organization_id=organization_id)
                          if str(member.get("email") or "").lower() == row["email"] and member.get("status") == "pending")
    else:
        if resend:
            raise ValueError("This pending invitation no longer exists. Review the roster again.")
        if not review["can_send"]:
            raise ValueError("No student seats available. Increase the seat limit or release unused seats.")
        access_expires_at = normalize_access_expiry(body.get("access_expires_at"))
        if access_expires_at and review["organization"].get("access_expires_at") and parse_access_expiry(access_expires_at) > parse_access_expiry(review["organization"]["access_expires_at"]):
            raise ValueError("Student access cannot end after the class end date.")
        membership = repository.save_membership({
            "organization_id": organization_id, "email": row["email"],
            "role": "student", "status": "pending", "seat_consumed": True,
            "access_expires_at": access_expires_at,
        }, updated_by_user_id=admin_user_id, updated_by_email=admin_email)
    sent, error = send_education_invite_email(
        membership=membership, organization=review["organization"], locale=body.get("locale", "en"),
    )
    return {"email": row["email"], "status": "sent" if sent else "email_failed",
            "access_expires_at": earliest_access_expiry(membership, review["organization"]),
            "email_sent": sent, "email_error": error,
            "invite_url": membership.get("invite_url", ""), "membership": membership}


def resend_teacher_invite(repository, body):
    organization = repository.get_organization(str(body.get("organization_id") or "").strip())
    if not organization or organization.get("plan_code") != "education" or organization.get("status") != "active" or not access_period_active(organization):
        raise ValueError("Select an active Education organization.")
    membership = repository.get_membership_by_invite_token(str(body.get("invite_token") or "").strip())
    if not membership or membership.get("organization_id") != organization.get("organization_id") or membership.get("role") != "teacher" or membership.get("status") != "pending" or not access_period_active(membership):
        raise ValueError("This teacher invitation is no longer pending.")
    sent, error = send_education_invite_email(membership=membership, organization=organization, locale=body.get("locale", "en"))
    return {"email_sent": sent, "email_error": error, "teacher_membership": membership}
