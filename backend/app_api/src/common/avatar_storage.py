from __future__ import annotations

import base64
import hashlib
import re
from typing import Any, Dict
from uuid import uuid4

from . import config
from .cloud_object_storage import (
    create_cloud_project_object_client,
    put_object_extra_args,
)

_DATA_URL_RE = re.compile(r"^data:(image/[a-zA-Z0-9.+-]+);base64,(.+)$", re.DOTALL)
_MAX_AVATAR_BYTES = 512 * 1024
_MIN_AVATAR_DIMENSION = 128
_MAX_AVATAR_DIMENSION = 2048
_AVATAR_CONTENT_TYPE = "image/jpeg"


class AvatarStorageError(ValueError):
    pass


def _safe_component(value: Any, *, fallback: str = "") -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_.=-]+", "-", str(value or "").strip()).strip("-._")
    return cleaned[:120] or fallback


def _decode_data_url(image_data: str) -> tuple[str, bytes]:
    raw = str(image_data or "").strip()
    match = _DATA_URL_RE.match(raw)
    if not match:
        raise AvatarStorageError("Avatar image must be a base64 data URL.")
    content_type = match.group(1).strip().lower()
    if content_type not in {_AVATAR_CONTENT_TYPE, "image/jpg"}:
        raise AvatarStorageError("Avatar image must be a JPEG.")
    try:
        payload = base64.b64decode(match.group(2), validate=True)
    except Exception as exc:
        raise AvatarStorageError("Avatar image data is invalid.") from exc
    if not payload:
        raise AvatarStorageError("Avatar image is empty.")
    if len(payload) > _MAX_AVATAR_BYTES:
        raise AvatarStorageError("Avatar image must be 512 KB or smaller.")
    if not (payload.startswith(b"\xff\xd8") and payload.endswith(b"\xff\xd9")):
        raise AvatarStorageError("Avatar image must be a valid JPEG.")
    width, height = _jpeg_dimensions(payload)
    if width < _MIN_AVATAR_DIMENSION or height < _MIN_AVATAR_DIMENSION:
        raise AvatarStorageError("Avatar image must be at least 128 x 128 pixels.")
    if width > _MAX_AVATAR_DIMENSION or height > _MAX_AVATAR_DIMENSION:
        raise AvatarStorageError("Avatar image must be 2048 x 2048 pixels or smaller.")
    return _AVATAR_CONTENT_TYPE, payload


def _jpeg_dimensions(payload: bytes) -> tuple[int, int]:
    index = 2
    length = len(payload)
    while index + 9 < length:
        if payload[index] != 0xFF:
            index += 1
            continue
        marker = payload[index + 1]
        index += 2
        if marker in {0xD8, 0xD9}:
            continue
        if marker == 0xDA:
            break
        if index + 2 > length:
            break
        segment_length = int.from_bytes(payload[index:index + 2], "big")
        if segment_length < 2 or index + segment_length > length:
            break
        if marker in {
            0xC0,
            0xC1,
            0xC2,
            0xC3,
            0xC5,
            0xC6,
            0xC7,
            0xC9,
            0xCA,
            0xCB,
            0xCD,
            0xCE,
            0xCF,
        }:
            height = int.from_bytes(payload[index + 3:index + 5], "big")
            width = int.from_bytes(payload[index + 5:index + 7], "big")
            if width > 0 and height > 0:
                return width, height
            break
        index += segment_length
    raise AvatarStorageError("Avatar image dimensions could not be read.")


class AvatarStorage:
    def __init__(self) -> None:
        self._client = None

    def _object_client(self) -> Any:
        if self._client is None:
            self._client = create_cloud_project_object_client()
        return self._client

    def is_configured(self) -> bool:
        return bool(config.CLOUD_PROJECT_DOCUMENTS_BUCKET and self._object_client())

    def put_avatar(self, *, user_id: str, image_data: str) -> Dict[str, Any]:
        safe_user_id = _safe_component(user_id, fallback="user")
        if not safe_user_id:
            raise AvatarStorageError("User id is required.")
        object_client = self._object_client()
        if not config.CLOUD_PROJECT_DOCUMENTS_BUCKET or object_client is None:
            raise AvatarStorageError("Avatar storage is not configured.")
        content_type, payload = _decode_data_url(image_data)
        digest = hashlib.sha256(payload).hexdigest()[:16]
        key = f"profile-avatars/users/{safe_user_id}/avatar-{digest}-{uuid4().hex}.jpg"
        object_client.put_object(
            Bucket=config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
            Key=key,
            Body=payload,
            ContentType=content_type,
            CacheControl="private, max-age=300",
            **put_object_extra_args(),
        )
        return {
            "avatar_object_bucket": config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
            "avatar_object_key": key,
            "avatar_content_type": content_type,
            "avatar_size_bytes": len(payload),
        }

    def delete_avatar_object(self, *, bucket: str = "", key: str = "") -> None:
        safe_bucket = str(bucket or config.CLOUD_PROJECT_DOCUMENTS_BUCKET or "").strip()
        safe_key = str(key or "").strip()
        object_client = self._object_client()
        if not safe_bucket or not safe_key or object_client is None:
            return
        try:
            object_client.delete_object(Bucket=safe_bucket, Key=safe_key)
        except Exception:
            return

    def avatar_url(self, profile: Dict[str, Any], *, expires_in: int = 3600) -> str:
        key = str(profile.get("avatar_object_key") or "").strip()
        bucket = str(profile.get("avatar_object_bucket") or config.CLOUD_PROJECT_DOCUMENTS_BUCKET or "").strip()
        if not key or not bucket:
            return str(profile.get("avatar_url") or "").strip()
        object_client = self._object_client()
        if object_client is None:
            return ""
        return object_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=max(60, min(int(expires_in or 3600), 86400)),
        )
