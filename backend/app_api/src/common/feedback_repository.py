from __future__ import annotations

import base64
import hashlib
import math
import re
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from boto3.dynamodb.conditions import Key
except (ImportError, ModuleNotFoundError):  # pragma: no cover - local dev/test fallback
    Key = None

try:
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        pass

    class BotoCoreError(Exception):
        pass

from . import config
from .repository import BillingRepository

FEEDBACK_BUCKET = "feedback"
FEEDBACK_MAX_MESSAGE_CHARS = 1500
FEEDBACK_MAX_MESSAGE_PREVIEW_CHARS = 180
FEEDBACK_MAX_CHAT_MESSAGES = 24
FEEDBACK_MAX_CHAT_TOTAL_CHARS = 8000
FEEDBACK_MAX_CONTEXT_DEPTH = 4
FEEDBACK_MAX_CONTEXT_ITEMS = 24
FEEDBACK_MAX_CONTEXT_STRING_CHARS = 320
FEEDBACK_MAX_SCREENSHOT_BYTES = 120 * 1024
FEEDBACK_ALLOWED_CATEGORIES = {"feedback", "bug_report"}
FEEDBACK_ALLOWED_SOURCES = {"home", "account", "daw_chat"}
_CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
_MULTISPACE_RE = re.compile(r"[ \t]+")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _utc_now_iso() -> str:
    return _utc_now().isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _preview_text(value: str, *, max_chars: int = FEEDBACK_MAX_MESSAGE_PREVIEW_CHARS) -> str:
    flattened = _safe_str(value.replace("\n", " "))
    flattened = _MULTISPACE_RE.sub(" ", flattened)
    if len(flattened) <= max_chars:
        return flattened
    return f"{flattened[: max_chars - 1].rstrip()}…"


def sanitize_feedback_text(
    value: Any,
    *,
    max_chars: int = FEEDBACK_MAX_MESSAGE_CHARS,
    preserve_newlines: bool = True,
) -> str:
    text = str(value or "").replace("\r\n", "\n").replace("\r", "\n")
    text = _CONTROL_CHARS_RE.sub("", text)
    lines = [_MULTISPACE_RE.sub(" ", line).strip() for line in text.split("\n")]
    if preserve_newlines:
        normalized = "\n".join(lines)
        normalized = re.sub(r"\n{3,}", "\n\n", normalized)
    else:
        normalized = " ".join(line for line in lines if line)
    normalized = normalized.strip()
    if len(normalized) <= max_chars:
        return normalized
    return normalized[:max_chars].rstrip()


class FeedbackNotFoundError(Exception):
    pass


class FeedbackRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        self._billing_repo = (
            BillingRepository()
            if boto3 is not None and config.FEEDBACK_SUBMISSIONS_TABLE
            else None
        )

        if self._ddb is not None and config.FEEDBACK_SUBMISSIONS_TABLE:
            self._table = self._ddb.Table(config.FEEDBACK_SUBMISSIONS_TABLE)

    def create_submission(
        self,
        *,
        user_id: str,
        claims: Dict[str, Any],
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Feedback submissions table is not configured.")

        category = self._normalize_category(payload.get("category"))
        source = self._normalize_source(payload.get("source"))
        message = sanitize_feedback_text(payload.get("message"))
        if not message:
            raise ValueError("Feedback message cannot be empty.")

        context = self._sanitize_context(payload.get("context"))
        screenshot = self._sanitize_screenshot(payload.get("screenshot"))
        client = self._sanitize_client(payload.get("client"))
        allow_email_contact = self._sanitize_allow_email_contact(
            payload.get("allow_email_contact")
        )

        now = _utc_now_iso()
        submission_id = f"feedback_{_utc_now().strftime('%Y%m%d%H%M%S')}_{uuid.uuid4().hex[:10]}"
        email = _safe_str(claims.get("email")).lower()
        app_profile = self._billing_repo.get_user_profile(user_id) if self._billing_repo is not None else {}
        display_name = sanitize_feedback_text(
            app_profile.get("display_name") or claims.get("name"),
            max_chars=120,
            preserve_newlines=False,
        )
        username = sanitize_feedback_text(
            app_profile.get("username"),
            max_chars=60,
            preserve_newlines=False,
        )

        item = {
            "submission_id": submission_id,
            "bucket": FEEDBACK_BUCKET,
            "created_at": now,
            "category": category,
            "source": source,
            "message": message,
            "message_preview": _preview_text(message),
            "user_id": user_id,
            "user_email": email,
            "display_name": display_name,
            "username": username,
            "client": client,
            "allow_email_contact": allow_email_contact,
            "has_context": bool(context),
            "has_screenshot": bool(screenshot),
        }
        if context:
            item["context"] = context
        if screenshot:
            item["screenshot"] = screenshot

        self._table.put_item(Item=self._coerce_for_dynamodb(item))
        return {
            "submission_id": submission_id,
            "created_at": now,
            "category": category,
            "source": source,
            "message_preview": item["message_preview"],
        }

    def list_submissions(self, *, limit: int = 50) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Feedback submissions table is not configured.")
        safe_limit = max(1, min(_safe_int(limit) or 50, 100))
        items: list[Dict[str, Any]] = []
        warnings: list[str] = []

        if Key is not None:
            try:
                result = self._table.query(
                    IndexName="created_at_idx",
                    KeyConditionExpression=Key("bucket").eq(FEEDBACK_BUCKET),
                    ScanIndexForward=False,
                    Limit=safe_limit,
                )
                items = [item for item in result.get("Items", []) if isinstance(item, dict)]
            except (BotoCoreError, ClientError):
                warnings.append("feedback_created_at_idx_unavailable")

        if not items:
            scan_limit = max(safe_limit, 100)
            result = self._table.scan(Limit=scan_limit)
            items = [
                item
                for item in result.get("Items", [])
                if isinstance(item, dict)
                and _safe_str(item.get("bucket")) == FEEDBACK_BUCKET
            ]
            items.sort(key=lambda item: _safe_str(item.get("created_at")), reverse=True)
            items = items[:safe_limit]

        return {
            "generated_at": _utc_now_iso(),
            "limit": safe_limit,
            "warnings": warnings,
            "submissions": [self._serialize_summary(item) for item in items],
        }

    def get_submission(self, submission_id: str) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Feedback submissions table is not configured.")
        safe_submission_id = _safe_str(submission_id)
        if not safe_submission_id:
            raise ValueError("Submission ID is required.")

        try:
            item = self._table.get_item(Key={"submission_id": safe_submission_id}).get("Item")
        except (BotoCoreError, ClientError) as exc:
            raise RuntimeError("Could not load feedback submission.") from exc

        if not isinstance(item, dict):
            raise FeedbackNotFoundError("Feedback submission not found.")
        return self._serialize_detail(item)

    def _serialize_summary(self, item: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "submission_id": _safe_str(item.get("submission_id")),
            "created_at": _safe_str(item.get("created_at")),
            "category": _safe_str(item.get("category")) or "feedback",
            "source": _safe_str(item.get("source")) or "home",
            "message_preview": _safe_str(item.get("message_preview"))
            or _preview_text(_safe_str(item.get("message"))),
            "user_id": _safe_str(item.get("user_id")),
            "user_email": _safe_str(item.get("user_email")),
            "display_name": _safe_str(item.get("display_name")),
            "username": _safe_str(item.get("username")),
            "allow_email_contact": bool(item.get("allow_email_contact")),
            "has_context": bool(item.get("has_context") or item.get("context")),
            "has_screenshot": bool(item.get("has_screenshot") or item.get("screenshot")),
            "client": self._sanitize_client(item.get("client")),
        }

    def _serialize_detail(self, item: Dict[str, Any]) -> Dict[str, Any]:
        summary = self._serialize_summary(item)
        summary["message"] = sanitize_feedback_text(item.get("message"))
        context = self._sanitize_context(item.get("context"))
        screenshot = self._sanitize_screenshot(item.get("screenshot"))
        if context:
            summary["context"] = context
        if screenshot:
            summary["screenshot"] = screenshot
        return summary

    def _normalize_category(self, value: Any) -> str:
        normalized = _safe_str(value).lower()
        if normalized not in FEEDBACK_ALLOWED_CATEGORIES:
            raise ValueError("Feedback category is invalid.")
        return normalized

    def _normalize_source(self, value: Any) -> str:
        normalized = _safe_str(value).lower()
        if normalized not in FEEDBACK_ALLOWED_SOURCES:
            raise ValueError("Feedback source is invalid.")
        return normalized

    def _sanitize_client(self, raw: Any) -> Dict[str, Any]:
        if not isinstance(raw, dict):
            return {}
        client = dict(raw)
        result = {
            "platform": sanitize_feedback_text(
                client.get("platform"),
                max_chars=32,
                preserve_newlines=False,
            ),
            "app_version": sanitize_feedback_text(
                client.get("app_version"),
                max_chars=32,
                preserve_newlines=False,
            ),
            "locale": sanitize_feedback_text(
                client.get("locale"),
                max_chars=24,
                preserve_newlines=False,
            ),
        }
        return {
            key: value
            for key, value in result.items()
            if _safe_str(value)
        }

    def _sanitize_context(self, raw: Any) -> Dict[str, Any]:
        if not isinstance(raw, dict):
            return {}

        context = dict(raw)
        result: Dict[str, Any] = {}
        chat_history = self._sanitize_chat_history(context.get("chat_history"))
        project_settings = self._sanitize_json_value(
            context.get("project_settings"),
            depth=0,
        )
        if chat_history:
            result["chat_history"] = chat_history
        if isinstance(project_settings, dict) and project_settings:
            result["project_settings"] = project_settings
        return result

    def _sanitize_allow_email_contact(self, raw: Any) -> bool:
        if isinstance(raw, bool):
            return raw
        if raw in (0, 1):
            return bool(raw)
        normalized = _safe_str(raw).lower()
        if not normalized:
            return False
        if normalized in {"true", "1", "yes", "y", "on"}:
            return True
        if normalized in {"false", "0", "no", "n", "off"}:
            return False
        raise ValueError("Email contact consent is invalid.")

    def _sanitize_chat_history(self, raw: Any) -> list[Dict[str, str]]:
        if not isinstance(raw, list):
            return []

        items: list[Dict[str, str]] = []
        total_chars = 0
        for entry in raw[:FEEDBACK_MAX_CHAT_MESSAGES]:
            if not isinstance(entry, dict):
                continue
            role = _safe_str(entry.get("role")).lower()
            if role not in {"user", "assistant", "system"}:
                continue
            remaining = FEEDBACK_MAX_CHAT_TOTAL_CHARS - total_chars
            if remaining <= 0:
                break
            content = sanitize_feedback_text(
                entry.get("content"),
                max_chars=min(remaining, 1200),
            )
            if not content:
                continue
            items.append({"role": role, "content": content})
            total_chars += len(content)
        return items

    def _sanitize_json_value(self, value: Any, *, depth: int) -> Any:
        if depth >= FEEDBACK_MAX_CONTEXT_DEPTH:
            return None
        if isinstance(value, dict):
            result: Dict[str, Any] = {}
            for raw_key, raw_value in list(value.items())[:FEEDBACK_MAX_CONTEXT_ITEMS]:
                key = sanitize_feedback_text(
                    raw_key,
                    max_chars=48,
                    preserve_newlines=False,
                )
                if not key:
                    continue
                sanitized = self._sanitize_json_value(raw_value, depth=depth + 1)
                if sanitized in (None, "", [], {}):
                    continue
                result[key] = sanitized
            return result
        if isinstance(value, list):
            result = []
            for item in value[:FEEDBACK_MAX_CONTEXT_ITEMS]:
                sanitized = self._sanitize_json_value(item, depth=depth + 1)
                if sanitized in (None, "", [], {}):
                    continue
                result.append(sanitized)
            return result
        if isinstance(value, bool):
            return value
        if isinstance(value, int):
            return max(min(value, 10**9), -(10**9))
        if isinstance(value, float):
            if not math.isfinite(value):
                return None
            return round(value, 4)
        return sanitize_feedback_text(
            value,
            max_chars=FEEDBACK_MAX_CONTEXT_STRING_CHARS,
            preserve_newlines=False,
        )

    def _sanitize_screenshot(self, raw: Any) -> Dict[str, Any]:
        if not isinstance(raw, dict):
            return {}

        screenshot = dict(raw)
        mime_type = _safe_str(screenshot.get("mime_type")).lower() or "image/jpeg"
        if mime_type not in {"image/jpeg", "image/png", "image/webp"}:
            raise ValueError("Screenshot format is invalid.")

        data_base64 = _safe_str(screenshot.get("data_base64"))
        if not data_base64:
            return {}
        try:
            decoded = base64.b64decode(data_base64, validate=True)
        except Exception as exc:
            raise ValueError("Screenshot data is invalid.") from exc
        if not decoded:
            return {}
        if len(decoded) > FEEDBACK_MAX_SCREENSHOT_BYTES:
            raise ValueError("Screenshot is too large.")

        normalized_base64 = base64.b64encode(decoded).decode("ascii")
        result: Dict[str, Any] = {
            "mime_type": mime_type,
            "data_base64": normalized_base64,
            "sha256": hashlib.sha256(decoded).hexdigest(),
            "size_bytes": len(decoded),
        }
        width = _safe_int(screenshot.get("width"))
        height = _safe_int(screenshot.get("height"))
        if width > 0:
            result["width"] = min(width, 4096)
        if height > 0:
            result["height"] = min(height, 4096)
        return result

    def _coerce_for_dynamodb(self, value: Any) -> Any:
        if isinstance(value, dict):
            return {
                key: self._coerce_for_dynamodb(item)
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [self._coerce_for_dynamodb(item) for item in value]
        if isinstance(value, bool):
            return value
        if isinstance(value, float):
            if not math.isfinite(value):
                return None
            # boto3 DynamoDB serializer rejects float; Decimal is required.
            return Decimal(str(value))
        return value
