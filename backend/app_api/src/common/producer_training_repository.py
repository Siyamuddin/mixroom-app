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
MULTIPART_THRESHOLD = 25_000_000
PART_SIZE = 8 * 1024 * 1024
MAX_CAPTURE_BYTES = 5_000_000_000

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
        part_checksums: list[str] | None = None,
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
            or str(existing.get("segmentation_version") or "") != segmentation_version
            or str(existing.get("media_manifest_sha256") or "") != manifest_checksum
        ):
            raise ValueError("session_id is already reserved with different content.")
        if existing and existing.get("status") == "deleted":
            raise ValueError("This capture was deleted.")
        if existing and existing.get("status") == "verified":
            return {"session_id": safe_session, "already_completed": True}
        if size_bytes > MULTIPART_THRESHOLD:
            return self._reserve_multipart(
                existing=existing,
                user_hash=user_hash,
                session_id=safe_session,
                key=key,
                size=size_bytes,
                metadata=metadata,
                part_checksums=part_checksums,
            )
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
        if size_bytes > MULTIPART_THRESHOLD:
            self._finish_multipart(user_hash, safe_session, pending_key, checksum)
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
        if actual_size != size_bytes or actual_size != int(
            metadata.get("expected-size") or 0
        ):
            raise ValueError("Uploaded bundle size did not match the reservation.")
        if checksum != str(metadata.get("sha256") or ""):
            raise ValueError("Uploaded bundle checksum did not match the reservation.")
        if schema_version != str(metadata.get("schema-version") or ""):
            raise ValueError(
                "Uploaded bundle schema version did not match the reservation."
            )
        if consent_version != str(metadata.get("consent-version") or ""):
            raise ValueError(
                "Uploaded bundle consent version did not match the reservation."
            )
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
            raise ValueError(
                "Uploaded bundle media manifest did not match the reservation."
            )
        expected_checksum = base64.b64encode(bytes.fromhex(checksum)).decode("ascii")
        if (
            size_bytes <= MULTIPART_THRESHOLD
            and str(head.get("ChecksumSHA256") or "") != expected_checksum
        ):
            raise ValueError("Stored bundle checksum verification failed.")
        uploaded = self._s3.get_object(
            Bucket=self._bucket,
            Key=final_key if already_completed else pending_key,
        )["Body"]
        try:
            if size_bytes > MULTIPART_THRESHOLD:
                from .producer_training_stream import validate_stream

                validate_stream(
                    uploaded,
                    checksum=checksum,
                    size=size_bytes,
                    expected={
                        "session_id": safe_session,
                        "schema_version": schema_version,
                        "consent_version": consent_version,
                        "feature_extractor_version": feature_extractor_version,
                        "segmentation_version": segmentation_version,
                    },
                    media_manifest=media_manifest,
                )
            else:
                _validate_bundle_document(
                    uploaded.read(),
                    session_id=safe_session,
                    schema_version=schema_version,
                    consent_version=consent_version,
                    feature_extractor_version=feature_extractor_version,
                    segmentation_version=segmentation_version,
                    media_manifest=media_manifest,
                )
        finally:
            uploaded.close()
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
        try:
            self._table.update_item(
                Key={"user_hash": user_hash, "session_id": safe_session},
                ConditionExpression="attribute_not_exists(deleted_at)",
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
        except Exception as exc:
            if (
                getattr(exc, "response", {}).get("Error", {}).get("Code")
                == "ConditionalCheckFailedException"
            ):
                self._s3.delete_object(Bucket=self._bucket, Key=final_key)
                raise ValueError("This capture was deleted.") from exc
            raise
        return {
            "accepted": True,
            "session_id": safe_session,
            "stored_at": stored_at,
            "object_key": final_key,
            "already_completed": already_completed,
        }

    def _reservation(self, user_id, session_id):
        return self._table.get_item(
            Key={
                "user_hash": _user_hash(user_id),
                "session_id": _safe(session_id, "unknown-session"),
            },
            ConsistentRead=True,
        ).get("Item", {})

    def upload_status(self, *, user_id, session_id):
        item = self._reservation(user_id, session_id)
        status = item.get("status", "missing")
        if status == "verifying":
            # Lambda can time out without running its exception handler.
            started = datetime.fromisoformat(item["updated_at"])
            if (datetime.now(timezone.utc) - started).total_seconds() > 960:
                status = "retry_needed"
        return {"status": status, "accepted": status == "verified"}

    def validate_reservation(
        self, *, user_id, session_id, checksum, size_bytes, media_manifest, **contract
    ):
        item = self._reservation(user_id, session_id)
        expected = dict(
            sha256=checksum,
            size_bytes=size_bytes,
            media_manifest_sha256=_manifest_checksum(media_manifest),
            **contract,
        )
        if not item or item.get("status") == "deleted":
            raise ValueError("Upload reservation is missing or deleted.")
        if any(item.get(key) != value for key, value in expected.items()):
            raise ValueError("Upload does not match its reservation.")

    def set_verification_status(self, *, user_id, session_id, status):
        try:
            self._table.update_item(
                Key={
                    "user_hash": _user_hash(user_id),
                    "session_id": _safe(session_id, "unknown-session"),
                },
                UpdateExpression="SET #status = :status, updated_at = :now",
                ConditionExpression="attribute_exists(session_id) AND #status <> :deleted AND #status <> :verified",
                ExpressionAttributeNames={"#status": "status"},
                ExpressionAttributeValues={
                    ":status": status,
                    ":now": datetime.now(timezone.utc).isoformat(),
                    ":deleted": "deleted",
                    ":verified": "verified",
                },
            )
            return True
        except Exception as exc:
            if (
                getattr(exc, "response", {}).get("Error", {}).get("Code")
                == "ConditionalCheckFailedException"
            ):
                return False
            raise

    def _multipart_parts(self, key, upload_id):
        parts = []
        marker = 0
        while True:
            page = self._s3.list_parts(
                Bucket=self._bucket,
                Key=key,
                UploadId=upload_id,
                PartNumberMarker=marker,
            )
            parts.extend(page.get("Parts", []))
            if not page.get("IsTruncated"):
                return parts
            marker = page["NextPartNumberMarker"]

    def _reserve_multipart(
        self, *, existing, user_hash, session_id, key, size, metadata, part_checksums
    ):
        count = (size + PART_SIZE - 1) // PART_SIZE
        if (
            not isinstance(part_checksums, list)
            or len(part_checksums) != count
            or any(
                not isinstance(c, str) or not re.fullmatch(r"[a-f0-9]{64}", c)
                for c in part_checksums
            )
        ):
            raise ValueError("Large captures require a checksum for every upload part.")
        if existing and existing.get("part_checksums") not in (None, part_checksums):
            raise ValueError("session_id is already reserved with different parts.")
        upload_id = (existing or {}).get("multipart_upload_id")
        parts = []
        if upload_id:
            try:
                parts = self._multipart_parts(key, upload_id)
            except Exception as exc:
                if (
                    getattr(exc, "response", {}).get("Error", {}).get("Code")
                    != "NoSuchUpload"
                ):
                    raise
                # Completion may have succeeded before a response was lost.
                for completed_key in (key, key.replace("pending/", "structured/", 1)):
                    try:
                        self._s3.head_object(Bucket=self._bucket, Key=completed_key)
                        return {
                            "session_id": session_id,
                            "multipart": True,
                            "parts": [],
                            "part_size": PART_SIZE,
                        }
                    except Exception as missing:
                        if getattr(missing, "response", {}).get("Error", {}).get(
                            "Code"
                        ) not in ("404", "NoSuchKey", "NotFound"):
                            raise
                upload_id = None
        if not upload_id:
            upload_id = self._s3.create_multipart_upload(
                Bucket=self._bucket,
                Key=key,
                ContentType=_CONTENT_TYPE,
                ServerSideEncryption="AES256",
                Metadata=metadata,
                ChecksumAlgorithm="SHA256",
            )["UploadId"]
            item = {
                "user_hash": user_hash,
                "session_id": session_id,
                "status": "reserved",
                "object_key": key,
                "sha256": metadata["sha256"],
                "size_bytes": size,
                "schema_version": metadata["schema-version"],
                "consent_version": metadata["consent-version"],
                "feature_extractor_version": metadata["feature-extractor-version"],
                "segmentation_version": metadata["segmentation-version"],
                "media_manifest_sha256": metadata["media-manifest-sha256"],
                "multipart_upload_id": upload_id,
                "part_checksums": part_checksums,
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "ingestion_status": "awaiting_upload",
            }
            # A competing reservation must not overwrite another upload ID.
            try:
                if existing and existing.get("multipart_upload_id"):
                    self._table.put_item(
                        Item=item,
                        ConditionExpression="multipart_upload_id = :old AND attribute_not_exists(deleted_at)",
                        ExpressionAttributeValues={
                            ":old": existing["multipart_upload_id"]
                        },
                    )
                else:
                    self._table.put_item(
                        Item=item,
                        ConditionExpression="attribute_not_exists(session_id)",
                    )
            except Exception:
                self._s3.abort_multipart_upload(
                    Bucket=self._bucket, Key=key, UploadId=upload_id
                )
                raise
        completed = {part["PartNumber"]: part for part in parts}
        uploads = []
        for index, digest in enumerate(part_checksums, 1):
            checksum = base64.b64encode(bytes.fromhex(digest)).decode()
            length = min(PART_SIZE, size - (index - 1) * PART_SIZE)
            part = completed.get(index)
            if (
                part
                and part.get("ChecksumSHA256") == checksum
                and int(part.get("Size", 0)) == length
            ):
                continue
            uploads.append(
                {
                    "part_number": index,
                    "size_bytes": length,
                    "upload_url": self._s3.generate_presigned_url(
                        "upload_part",
                        Params={
                            "Bucket": self._bucket,
                            "Key": key,
                            "UploadId": upload_id,
                            "PartNumber": index,
                            "ChecksumSHA256": checksum,
                            "ContentLength": length,
                        },
                        ExpiresIn=3600,
                    ),
                    "upload_headers": {"x-amz-checksum-sha256": checksum},
                }
            )
        return {
            "session_id": session_id,
            "multipart": True,
            "part_size": PART_SIZE,
            "parts": uploads,
        }

    def _finish_multipart(self, user_hash, session_id, key, checksum):
        item = self._table.get_item(
            Key={"user_hash": user_hash, "session_id": session_id}, ConsistentRead=True
        ).get("Item", {})
        if item.get("status") == "deleted":
            raise ValueError("This capture was deleted.")
        if item.get("sha256") != checksum:
            raise ValueError("Multipart reservation does not match.")
        if item.get("status") == "verified":
            return
        upload_id = item.get("multipart_upload_id")
        if not upload_id:
            raise ValueError("Multipart reservation is missing.")
        try:
            parts = self._multipart_parts(key, upload_id)
        except Exception as exc:
            if (
                getattr(exc, "response", {}).get("Error", {}).get("Code")
                == "NoSuchUpload"
            ):
                return
            raise
        checksums = item["part_checksums"]
        if len(parts) != len(checksums):
            raise ValueError("Multipart upload is incomplete.")
        ordered = sorted(parts, key=lambda p: p["PartNumber"])
        for index, part in enumerate(ordered, 1):
            expected_size = min(
                PART_SIZE, int(item["size_bytes"]) - (index - 1) * PART_SIZE
            )
            if (
                part["PartNumber"] != index
                or int(part["Size"]) != expected_size
                or part.get("ChecksumSHA256")
                != base64.b64encode(bytes.fromhex(checksums[index - 1])).decode()
            ):
                raise ValueError("Multipart part verification failed.")
        self._s3.complete_multipart_upload(
            Bucket=self._bucket,
            Key=key,
            UploadId=upload_id,
            MultipartUpload={
                "Parts": [
                    {k: part[k] for k in ("PartNumber", "ETag", "ChecksumSHA256")}
                    for part in ordered
                ]
            },
        )

    def delete_session(self, *, user_id: str, session_id: str) -> int:
        if not self.is_configured or self._s3 is None or self._table is None:
            raise RuntimeError("Producer training storage is not configured.")
        safe_session = _safe(session_id, "unknown-session")
        user_hash = _user_hash(user_id)
        item = self._table.get_item(
            Key={"user_hash": user_hash, "session_id": safe_session},
            ConsistentRead=True,
        ).get("Item", {})
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
        if item.get("multipart_upload_id"):
            try:
                self._s3.abort_multipart_upload(
                    Bucket=self._bucket,
                    Key=f"pending/user={user_hash}/session={safe_session}/bundle.json",
                    UploadId=item["multipart_upload_id"],
                )
            except Exception as exc:
                if (
                    getattr(exc, "response", {}).get("Error", {}).get("Code")
                    != "NoSuchUpload"
                ):
                    raise
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
        return len(keys)
