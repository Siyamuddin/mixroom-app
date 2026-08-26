from __future__ import annotations

import hashlib
import base64
import json
import re
from datetime import datetime, timezone
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover
    boto3 = None

from . import config

_SAFE_RE = re.compile(r"[^a-zA-Z0-9._-]+")
_CONTENT_TYPE = "application/vnd.mixroom.producer-training+json"
_LOCAL_PATH_RE = re.compile(
    r"(?:file://)?/(?:Users|Library|Applications|System|Volumes|private|var|tmp)/|[A-Za-z]:\\"
)
_FORBIDDEN_KEYS = frozenset(
    {
        "project_name",
        "client_name",
        "account_id",
        "email",
        "username",
        "filename",
        "file_name",
        "path",
        "source_path",
        "source_file",
        "source_file_path",
        "authorization",
        "access_token",
        "refresh_token",
        "id_token",
        "api_key",
    }
)


def _safe(value: Any, fallback: str) -> str:
    token = _SAFE_RE.sub("-", str(value or "").strip()).strip("-._")
    return (token or fallback)[:128]


def _user_hash(user_id: str) -> str:
    return hashlib.sha256(user_id.encode("utf-8")).hexdigest()[:24]


def _manifest_checksum(media_manifest: list[dict[str, Any]]) -> str:
    canonical = json.dumps(
        media_manifest,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _validate_bundle_privacy(value: Any, *, key: str = "") -> None:
    normalized_key = key.strip().lower()
    if normalized_key in _FORBIDDEN_KEYS or "filepath" in normalized_key:
        raise ValueError("Uploaded bundle contains a forbidden identifier field.")
    if isinstance(value, dict):
        for child_key, child in value.items():
            _validate_bundle_privacy(child, key=str(child_key))
    elif isinstance(value, list):
        for child in value:
            _validate_bundle_privacy(child, key=key)
    elif isinstance(value, str):
        if _LOCAL_PATH_RE.search(value) or re.search(r"Bearer\s+\S+", value, re.I):
            raise ValueError("Uploaded bundle contains a local path or credential.")


def _validate_bundle_document(
    raw: bytes,
    *,
    session_id: str,
    schema_version: str,
    consent_version: str,
    feature_extractor_version: str,
    segmentation_version: str,
    media_manifest: list[dict[str, Any]],
) -> None:
    try:
        document = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Uploaded bundle is not valid JSON.") from exc
    if not isinstance(document, dict):
        raise ValueError("Uploaded bundle must be a JSON object.")
    expected = {
        "session_id": session_id,
        "schema_version": schema_version,
        "consent_version": consent_version,
        "feature_extractor_version": feature_extractor_version,
        "segmentation_version": segmentation_version,
    }
    if any(str(document.get(key) or "") != value for key, value in expected.items()):
        raise ValueError("Uploaded bundle document did not match its reservation.")
    document_manifest = document.get("media_manifest")
    if not isinstance(document_manifest, list) or _manifest_checksum(
        document_manifest
    ) != _manifest_checksum(media_manifest):
        raise ValueError("Uploaded bundle document media manifest did not match.")
    _validate_bundle_privacy(document)


class ProducerTrainingRepository:
    def __init__(self) -> None:
        self._bucket = config.PRODUCER_TRAINING_BUCKET
        self._s3 = (
            boto3.client(
                "s3",
                region_name=config.AWS_REGION or None,
                endpoint_url=(
                    f"https://s3.{config.AWS_REGION}.amazonaws.com"
                    if config.AWS_REGION
                    else None
                ),
            )
            if boto3 is not None and self._bucket
            else None
        )
        table_name = config.PRODUCER_TRAINING_SESSIONS_TABLE
        self._table = (
            boto3.resource("dynamodb").Table(table_name)
            if boto3 is not None and table_name
            else None
        )

    @property
    def is_configured(self) -> bool:
        return self._s3 is not None and self._table is not None and bool(self._bucket)

    def reserve_upload(
        self,
        *,
        user_id: str,
        session_id: str,
        size_bytes: int,
        checksum: str,
        schema_version: str,
        consent_version: str,
        feature_extractor_version: str,
        segmentation_version: str,
        media_manifest: list[dict[str, Any]],
    ) -> Dict[str, Any]:
        if not self.is_configured or self._s3 is None or self._table is None:
            raise RuntimeError("Producer training storage is not configured.")
        safe_session = _safe(session_id, "unknown-session")
        user_hash = _user_hash(user_id)
        key = f"pending/user={user_hash}/session={safe_session}/bundle.json"
        manifest_checksum = _manifest_checksum(media_manifest)
        metadata = {
            "user-hash": user_hash,
            "session-id": safe_session,
            "sha256": checksum,
            "schema-version": _safe(schema_version, "unknown"),
            "consent-version": _safe(consent_version, "unknown"),
            "feature-extractor-version": _safe(feature_extractor_version, "unknown"),
            "segmentation-version": _safe(segmentation_version, "unknown"),
            "expected-size": str(size_bytes),
            "media-manifest-sha256": manifest_checksum,
        }
        now = datetime.now(timezone.utc).isoformat()
        existing = self._table.get_item(
            Key={"user_hash": user_hash, "session_id": safe_session},
            ConsistentRead=True,
        ).get("Item")
        if existing and (
            str(existing.get("sha256") or "") != checksum
            or int(existing.get("size_bytes") or 0) != size_bytes
            or str(existing.get("schema_version") or "") != schema_version
            or str(existing.get("consent_version") or "") != consent_version
            or str(existing.get("feature_extractor_version") or "")
            != feature_extractor_version
            or str(existing.get("segmentation_version") or "")
            != segmentation_version
            or str(existing.get("media_manifest_sha256") or "")
            != manifest_checksum
        ):
            raise ValueError("session_id is already reserved with different content.")
        self._table.put_item(
            Item={
                "user_hash": user_hash,
                "session_id": safe_session,
                "status": "reserved",
                "object_key": key,
                "sha256": checksum,
                "size_bytes": size_bytes,
                "schema_version": schema_version,
                "consent_version": consent_version,
                "feature_extractor_version": feature_extractor_version,
                "segmentation_version": segmentation_version,
                "media_manifest_sha256": manifest_checksum,
                "media_count": len(media_manifest),
                "reserved_at": str((existing or {}).get("reserved_at") or now),
                "updated_at": now,
                "ingestion_status": "awaiting_upload",
            }
        )
        checksum_base64 = base64.b64encode(bytes.fromhex(checksum)).decode("ascii")
        upload_url = self._s3.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self._bucket,
                "Key": key,
                "ContentType": _CONTENT_TYPE,
                "ServerSideEncryption": "AES256",
                "Metadata": metadata,
                "ChecksumSHA256": checksum_base64,
            },
            ExpiresIn=900,
        )
        return {
            "session_id": safe_session,
            "upload_url": upload_url,
            "upload_headers": {
                "content-type": _CONTENT_TYPE,
                "x-amz-server-side-encryption": "AES256",
                "x-amz-checksum-sha256": checksum_base64,
                **{f"x-amz-meta-{name}": value for name, value in metadata.items()},
            },
            "expires_in_seconds": 900,
        }

    def complete_upload(
        self,
        *,
        user_id: str,
        session_id: str,
        size_bytes: int,
        checksum: str,
        schema_version: str,
        consent_version: str,
        feature_extractor_version: str,
        segmentation_version: str,
        media_manifest: list[dict[str, Any]],
    ) -> Dict[str, Any]:
        if not self.is_configured or self._s3 is None or self._table is None:
            raise RuntimeError("Producer training storage is not configured.")
        safe_session = _safe(session_id, "unknown-session")
        user_hash = _user_hash(user_id)
        pending_key = f"pending/user={user_hash}/session={safe_session}/bundle.json"
        final_key = f"structured/user={user_hash}/session={safe_session}/bundle.json"
        already_completed = False
        try:
            head = self._s3.head_object(
                Bucket=self._bucket, Key=pending_key, ChecksumMode="ENABLED"
            )
        except Exception:
            head = self._s3.head_object(
                Bucket=self._bucket, Key=final_key, ChecksumMode="ENABLED"
            )
            already_completed = True
        actual_size = int(head.get("ContentLength") or 0)
        metadata = head.get("Metadata") or {}
        manifest_checksum = _manifest_checksum(media_manifest)
        if actual_size != size_bytes or actual_size != int(metadata.get("expected-size") or 0):
            raise ValueError("Uploaded bundle size did not match the reservation.")
        if checksum != str(metadata.get("sha256") or ""):
            raise ValueError("Uploaded bundle checksum did not match the reservation.")
        if schema_version != str(metadata.get("schema-version") or ""):
            raise ValueError("Uploaded bundle schema version did not match the reservation.")
        if consent_version != str(metadata.get("consent-version") or ""):
            raise ValueError("Uploaded bundle consent version did not match the reservation.")
        if feature_extractor_version != str(
            metadata.get("feature-extractor-version") or ""
        ):
            raise ValueError(
                "Uploaded bundle feature extractor version did not match the reservation."
            )
        if segmentation_version != str(metadata.get("segmentation-version") or ""):
            raise ValueError(
                "Uploaded bundle segmentation version did not match the reservation."
            )
        if manifest_checksum != str(metadata.get("media-manifest-sha256") or ""):
            raise ValueError("Uploaded bundle media manifest did not match the reservation.")
        expected_checksum = base64.b64encode(bytes.fromhex(checksum)).decode("ascii")
        if str(head.get("ChecksumSHA256") or "") != expected_checksum:
            raise ValueError("Stored bundle checksum verification failed.")
        uploaded = self._s3.get_object(
            Bucket=self._bucket,
            Key=final_key if already_completed else pending_key,
        )["Body"].read()
        _validate_bundle_document(
            uploaded,
            session_id=safe_session,
            schema_version=schema_version,
            consent_version=consent_version,
            feature_extractor_version=feature_extractor_version,
            segmentation_version=segmentation_version,
            media_manifest=media_manifest,
        )
        if not already_completed:
            self._s3.copy_object(
                Bucket=self._bucket,
                Key=final_key,
                CopySource={"Bucket": self._bucket, "Key": pending_key},
                MetadataDirective="COPY",
                ServerSideEncryption="AES256",
                ContentType=_CONTENT_TYPE,
            )
            self._s3.delete_object(Bucket=self._bucket, Key=pending_key)
        stored_at = datetime.now(timezone.utc).isoformat()
        self._table.update_item(
            Key={"user_hash": user_hash, "session_id": safe_session},
            UpdateExpression=(
                "SET #status = :status, ingestion_status = :ingestion, "
                "object_key = :object_key, stored_at = :stored_at, updated_at = :updated_at"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":status": "verified",
                ":ingestion": "ready_for_conversion",
                ":object_key": final_key,
                ":stored_at": stored_at,
                ":updated_at": stored_at,
            },
        )
        return {
            "accepted": True,
            "session_id": safe_session,
            "stored_at": stored_at,
            "object_key": final_key,
            "already_completed": already_completed,
        }

    def delete_session(self, *, user_id: str, session_id: str) -> int:
        if not self.is_configured or self._s3 is None or self._table is None:
            raise RuntimeError("Producer training storage is not configured.")
        safe_session = _safe(session_id, "unknown-session")
        user_hash = _user_hash(user_id)
        keys = [
            f"pending/user={user_hash}/session={safe_session}/bundle.json",
            f"structured/user={user_hash}/session={safe_session}/bundle.json",
        ]
        media_prefix = f"media/user={user_hash}/session={safe_session}/"
        listed = self._s3.list_objects_v2(Bucket=self._bucket, Prefix=media_prefix)
        keys.extend(
            str(item.get("Key"))
            for item in listed.get("Contents") or []
            if item.get("Key")
        )
        for key in keys:
            self._s3.delete_object(Bucket=self._bucket, Key=key)
        deleted_at = datetime.now(timezone.utc).isoformat()
        self._table.update_item(
            Key={"user_hash": user_hash, "session_id": safe_session},
            UpdateExpression=(
                "SET #status = :status, ingestion_status = :ingestion, "
                "deleted_at = :deleted_at, updated_at = :updated_at"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":status": "deleted",
                ":ingestion": "deleted",
                ":deleted_at": deleted_at,
                ":updated_at": deleted_at,
            },
        )
        return len(keys)
