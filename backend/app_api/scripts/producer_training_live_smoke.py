#!/usr/bin/env python3
"""Run a reversible production smoke test for producer-training ingestion."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
import uuid
from urllib.request import Request, urlopen


def _aws(args: list[str]) -> str:
    result = subprocess.run(
        ["aws", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack", default="mixroom-app-api-prod")
    parser.add_argument("--region", default="ap-northeast-2")
    args = parser.parse_args()

    function_name = _aws(
        [
            "cloudformation",
            "describe-stack-resource",
            "--stack-name",
            args.stack,
            "--logical-resource-id",
            "ProducerTrainingApiFunction",
            "--region",
            args.region,
            "--query",
            "StackResourceDetail.PhysicalResourceId",
            "--output",
            "text",
        ]
    )

    session_id = f"smoke-{uuid.uuid4().hex}"
    bundle = {
        "schema_version": "producer_training_capture_v4",
        "consent_version": "producer_training_2026_08_v1",
        "feature_extractor_version": "producer_audio_features_v1",
        "segmentation_version": "producer_episode_segmentation_v1",
        "session_id": session_id,
        "media_manifest": [],
        "episodes": [],
    }
    body = json.dumps(bundle, sort_keys=True, separators=(",", ":")).encode()
    checksum = hashlib.sha256(body).hexdigest()
    contract = {
        "session_id": session_id,
        "size_bytes": len(body),
        "sha256": checksum,
        "schema_version": bundle["schema_version"],
        "consent_version": bundle["consent_version"],
        "feature_extractor_version": bundle["feature_extractor_version"],
        "segmentation_version": bundle["segmentation_version"],
        "media_manifest": [],
    }

    def invoke(method: str, path: str, payload: dict | None = None) -> dict:
        event = {
            "rawPath": path,
            "requestContext": {
                "http": {"method": method},
                "authorizer": {
                    "jwt": {
                        "claims": {
                            "iss": "mixroom-native-auth",
                            "sub": "producer-training-live-smoke",
                            "sid": "smoke-session",
                            "token_use": "access",
                        }
                    }
                },
            },
            "body": json.dumps(payload or {}),
        }
        with tempfile.NamedTemporaryFile(suffix=".json") as response_file:
            _aws(
                [
                    "lambda",
                    "invoke",
                    "--function-name",
                    function_name,
                    "--invocation-type",
                    "RequestResponse",
                    "--cli-binary-format",
                    "raw-in-base64-out",
                    "--payload",
                    json.dumps(event),
                    "--region",
                    args.region,
                    response_file.name,
                ]
            )
            response_file.seek(0)
            result = json.loads(response_file.read())
        status = int(result.get("statusCode") or 0)
        if status < 200 or status >= 300:
            raise RuntimeError(f"{method} {path} failed: {status} {result.get('body')}")
        return json.loads(result.get("body") or "{}")

    try:
        reservation = invoke(
            "POST", "/v1/producer-training/sessions/uploads", contract
        )
        request = Request(
            reservation["upload_url"],
            data=body,
            headers=reservation["upload_headers"],
            method="PUT",
        )
        with urlopen(request, timeout=30) as response:
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"Signed upload failed: {response.status}")
        completed = invoke(
            "POST",
            f"/v1/producer-training/sessions/{session_id}/complete",
            contract,
        )
        print(
            json.dumps(
                {
                    "reserve": "ok",
                    "signed_upload": "ok",
                    "complete": "ok",
                    "verified_object": completed.get("object_key"),
                },
                indent=2,
            )
        )
    finally:
        invoke("DELETE", f"/v1/producer-training/sessions/{session_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
