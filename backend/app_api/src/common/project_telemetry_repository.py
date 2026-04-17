from __future__ import annotations

import gzip
import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

from . import config

_SAFE_KEY_CHARS_RE = re.compile(r"[^a-zA-Z0-9._-]+")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _safe_key_part(value: Any, *, fallback: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return fallback
    safe = _SAFE_KEY_CHARS_RE.sub("-", raw).strip("-._")
    if not safe:
        return fallback
    return safe[:96]


def _stable_hash(value: Any) -> str:
    return hashlib.sha256(str(value or "").encode("utf-8")).hexdigest()[:16]


class ProjectTelemetryRepository:
    def __init__(self) -> None:
        self._bucket = config.TELEMETRY_PROJECT_SNAPSHOTS_BUCKET
        self._s3 = boto3.client("s3") if boto3 is not None and self._bucket else None

    @property
    def is_configured(self) -> bool:
        return self._s3 is not None and bool(self._bucket)

    def store_snapshot(
        self,
        *,
        user_id: str,
        payload: Dict[str, Any],
        project_id: str,
    ) -> Dict[str, Any]:
        if not self.is_configured or self._s3 is None or not self._bucket:
            raise RuntimeError("Project telemetry bucket is not configured.")

        now = _utc_now()
        serialized = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        compressed = gzip.compress(serialized, compresslevel=6)

        object_id = f"telemetry_{now.strftime('%Y%m%dT%H%M%S')}_{uuid.uuid4().hex[:12]}"
        key = (
            f"year={now.strftime('%Y')}/"
            f"month={now.strftime('%m')}/"
            f"day={now.strftime('%d')}/"
            f"user={_stable_hash(user_id)}/"
            f"project={_safe_key_part(project_id, fallback='unknown-project')}/"
            f"{object_id}.json.gz"
        )

        self._s3.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=compressed,
            ContentType="application/json",
            ContentEncoding="gzip",
            ServerSideEncryption="AES256",
            Metadata={
                "user-hash": _stable_hash(user_id),
                "project-id": _safe_key_part(project_id, fallback="unknown-project"),
            },
        )

        return {
            "object_key": key,
            "object_id": object_id,
            "size_bytes": len(serialized),
            "compressed_size_bytes": len(compressed),
            "stored_at": now.isoformat(),
        }
