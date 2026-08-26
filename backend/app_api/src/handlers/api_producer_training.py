from __future__ import annotations

import logging
import re
from typing import Any, Dict

from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.producer_training_repository import ProducerTrainingRepository
from common.rate_limits import RequestRateLimiter

repo = ProducerTrainingRepository()
rate_limiter = RequestRateLimiter()
_SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
_SESSION_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
_SUPPORTED_SCHEMA_VERSIONS = frozenset({"producer_training_capture_v4"})
logger = logging.getLogger(__name__)


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    context = event.get("requestContext") or {}
    http = context.get("http") or {} if isinstance(context, dict) else {}
    return str(http.get("method") or event.get("httpMethod") or "").upper()


def _validated_fields(body: Dict[str, Any]) -> Dict[str, Any]:
    session_id = str(body.get("session_id") or "").strip()
    checksum = str(body.get("sha256") or "").strip().lower()
    size_bytes = int(body.get("size_bytes") or 0)
    if not _SESSION_ID_RE.fullmatch(session_id):
        raise ValueError("A valid session_id is required.")
    if not _SHA256_RE.fullmatch(checksum):
        raise ValueError("A valid sha256 checksum is required.")
    if size_bytes <= 0 or size_bytes > 25_000_000:
        raise ValueError("size_bytes must be between 1 and 25000000.")
    return {
        "session_id": session_id,
        "checksum": checksum,
        "size_bytes": size_bytes,
    }


def _validated_capture_contract(body: Dict[str, Any]) -> Dict[str, Any]:
    schema_version = str(body.get("schema_version") or "").strip()
    consent_version = str(body.get("consent_version") or "").strip()
    feature_extractor_version = str(
        body.get("feature_extractor_version") or ""
    ).strip()
    segmentation_version = str(body.get("segmentation_version") or "").strip()
    media_manifest = body.get("media_manifest")
    if schema_version not in _SUPPORTED_SCHEMA_VERSIONS:
        raise ValueError("Unsupported producer training schema_version.")
    if not consent_version or len(consent_version) > 128:
        raise ValueError("A valid consent_version is required.")
    if not feature_extractor_version or len(feature_extractor_version) > 128:
        raise ValueError("A valid feature_extractor_version is required.")
    if not segmentation_version or len(segmentation_version) > 128:
        raise ValueError("A valid segmentation_version is required.")
    if not isinstance(media_manifest, list) or len(media_manifest) > 20:
        raise ValueError("media_manifest must be an array with at most 20 items.")
    if any(not isinstance(item, dict) for item in media_manifest):
        raise ValueError("Every media_manifest item must be an object.")
    return {
        "schema_version": schema_version,
        "consent_version": consent_version,
        "feature_extractor_version": feature_extractor_version,
        "segmentation_version": segmentation_version,
        "media_manifest": media_manifest,
    }


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not repo.is_configured:
        return json_response(503, {"error": "Producer training storage is not configured."})
    decision = rate_limiter.enforce(
        scope_key=f"producer_training:{user_id}",
        limit=120,
        window_seconds=3600,
        block_seconds=300,
    )
    if not decision.allowed:
        return json_response(429, {"error": "Too many capture uploads."})

    path = _path(event)
    method = _method(event)
    try:
        if method == "POST" and path.endswith("/v1/producer-training/sessions/uploads"):
            body = parse_json_body(event, max_bytes=100_000)
            fields = _validated_fields(body)
            contract = _validated_capture_contract(body)
            return json_response(
                201,
                repo.reserve_upload(
                    user_id=user_id,
                    **fields,
                    **contract,
                ),
            )

        marker = "/v1/producer-training/sessions/"
        if marker in path:
            suffix = path.split(marker, 1)[1]
            if method == "POST" and suffix.endswith("/complete"):
                body = parse_json_body(event, max_bytes=100_000)
                fields = _validated_fields(
                    {**body, "session_id": suffix[: -len("/complete")]}
                )
                contract = _validated_capture_contract(body)
                return json_response(
                    202,
                    repo.complete_upload(
                        user_id=user_id,
                        **fields,
                        **contract,
                    ),
                )
            if method == "DELETE" and suffix and "/" not in suffix:
                count = repo.delete_session(user_id=user_id, session_id=suffix)
                return json_response(
                    200, {"deleted": True, "deleted_objects": count}
                )
    except RequestBodyError as exc:
        return json_response(exc.status_code, {"error": exc.message})
    except ValueError as exc:
        status = 409 if "already reserved" in str(exc) else 400
        return json_response(status, {"error": str(exc)})
    except Exception:
        logger.exception("Producer training storage operation failed")
        return json_response(
            503, {"error": "Producer training storage operation failed."}
        )
    return json_response(404, {"error": "Not found"})
