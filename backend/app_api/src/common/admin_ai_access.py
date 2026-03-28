from __future__ import annotations

from . import config
from .admin_access_repository import normalize_email


def ai_admin_editor_emails() -> set[str]:
    return {
        normalize_email(email)
        for email in config.AI_ADMIN_EDITOR_EMAILS.split(",")
        if normalize_email(email)
    } or {"andrew@mixroom.ai"}


def can_edit_ai_settings(email: str) -> bool:
    return normalize_email(email) in ai_admin_editor_emails()
