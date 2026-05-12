from __future__ import annotations

from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from botocore.config import Config
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    Config = None

from . import config
from .secrets import load_cloud_project_r2_credentials

_R2_PROVIDER = "r2"
_S3_PROVIDER = "s3"
_S3_MANAGED_SSE = "AES256"


def cloud_project_storage_provider() -> str:
    provider = (config.CLOUD_PROJECT_STORAGE_PROVIDER or _S3_PROVIDER).strip().lower()
    return _R2_PROVIDER if provider == _R2_PROVIDER else _S3_PROVIDER


def cloud_project_storage_mode() -> str:
    return "blob_mixroom"


def legacy_cloud_project_storage_mode() -> str:
    return "s3_mixroom"


def supports_object_versions() -> bool:
    return cloud_project_storage_provider() == _S3_PROVIDER


def create_cloud_project_object_client() -> Any:
    if boto3 is None:
        return None
    if cloud_project_storage_provider() != _R2_PROVIDER:
        return boto3.client("s3")

    credentials = load_cloud_project_r2_credentials()
    kwargs: Dict[str, Any] = {
        "service_name": "s3",
        "endpoint_url": credentials["endpoint_url"],
        "aws_access_key_id": credentials["access_key_id"],
        "aws_secret_access_key": credentials["secret_access_key"],
        "region_name": "auto",
    }
    if Config is not None:
        kwargs["config"] = Config(signature_version="s3v4")
    return boto3.client(**kwargs)


def put_object_extra_args() -> Dict[str, str]:
    if cloud_project_storage_provider() == _R2_PROVIDER:
        return {}
    return {"ServerSideEncryption": _S3_MANAGED_SSE}


def upload_headers(content_type: str) -> Dict[str, str]:
    headers = {"content-type": content_type}
    if cloud_project_storage_provider() != _R2_PROVIDER:
        headers["x-amz-server-side-encryption"] = _S3_MANAGED_SSE
    return headers


def copy_object_extra_args() -> Dict[str, str]:
    if cloud_project_storage_provider() == _R2_PROVIDER:
        return {}
    return {"ServerSideEncryption": _S3_MANAGED_SSE}
