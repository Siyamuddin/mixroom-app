import importlib
import json
import unittest
from types import SimpleNamespace

import support  # noqa: F401

module = importlib.import_module("handlers.api_producer_training")


class _Repo:
    is_configured = True

    def __init__(self):
        self.reservations = []
        self.completions = []
        self.deletions = []

    def reserve_upload(
        self,
        *,
        user_id,
        session_id,
        checksum,
        size_bytes,
        schema_version,
        consent_version,
        feature_extractor_version,
        segmentation_version,
        media_manifest,
    ):
        kwargs = locals()
        kwargs.pop("self")
        self.reservations.append(kwargs)
        return {
            "session_id": kwargs["session_id"],
            "upload_url": "https://upload.example/session",
            "upload_headers": {"content-type": "application/json"},
        }

    def complete_upload(
        self,
        *,
        user_id,
        session_id,
        checksum,
        size_bytes,
        schema_version,
        consent_version,
        feature_extractor_version,
        segmentation_version,
        media_manifest,
    ):
        kwargs = locals()
        kwargs.pop("self")
        self.completions.append(kwargs)
        return {"accepted": True, "session_id": kwargs["session_id"]}

    def delete_session(self, **kwargs):
        self.deletions.append(kwargs)
        return 3


class _Limiter:
    def enforce(self, **_kwargs):
        return SimpleNamespace(allowed=True, retry_after_seconds=0)


class ProducerTrainingApiTests(unittest.TestCase):
    def setUp(self):
        self.original_repo = module.repo
        self.original_limiter = module.rate_limiter
        self.original_extract = module.extract_claims_from_event
        self.repo = _Repo()
        module.repo = self.repo
        module.rate_limiter = _Limiter()
        module.extract_claims_from_event = lambda _event: {"sub": "producer-1"}

    def tearDown(self):
        module.repo = self.original_repo
        module.rate_limiter = self.original_limiter
        module.extract_claims_from_event = self.original_extract

    def _event(self, method, path, body=None):
        return {
            "rawPath": path,
            "requestContext": {"http": {"method": method}},
            "body": json.dumps(body or {}),
        }

    def test_reserves_idempotent_signed_upload(self):
        checksum = "a" * 64
        result = module.handler(
            self._event(
                "POST",
                "/v1/producer-training/sessions/uploads",
                {
                    "session_id": "session-1",
                    "size_bytes": 512,
                    "sha256": checksum,
                    "schema_version": "producer_training_capture_v4",
                    "consent_version": "consent-v1",
                    "feature_extractor_version": "features-v1",
                    "segmentation_version": "segments-v1",
                    "media_manifest": [],
                },
            ),
            object(),
        )
        self.assertEqual(result["statusCode"], 201)
        self.assertEqual(self.repo.reservations[0]["user_id"], "producer-1")
        self.assertIn("upload_url", json.loads(result["body"]))

    def test_completes_and_deletes_only_authenticated_users_session(self):
        checksum = "b" * 64
        complete = module.handler(
            self._event(
                "POST",
                "/v1/producer-training/sessions/session-1/complete",
                {
                    "size_bytes": 512,
                    "sha256": checksum,
                    "schema_version": "producer_training_capture_v4",
                    "consent_version": "consent-v1",
                    "feature_extractor_version": "features-v1",
                    "segmentation_version": "segments-v1",
                    "media_manifest": [],
                },
            ),
            object(),
        )
        deleted = module.handler(
            self._event(
                "DELETE", "/v1/producer-training/sessions/session-1"
            ),
            object(),
        )
        self.assertEqual(complete["statusCode"], 202)
        self.assertEqual(deleted["statusCode"], 200)
        self.assertEqual(self.repo.completions[0]["user_id"], "producer-1")
        self.assertEqual(self.repo.deletions[0]["session_id"], "session-1")

    def test_rejects_invalid_checksum(self):
        result = module.handler(
            self._event(
                "POST",
                "/v1/producer-training/sessions/uploads",
                {"session_id": "session-1", "size_bytes": 10, "sha256": "bad"},
            ),
            object(),
        )
        self.assertEqual(result["statusCode"], 400)

    def test_rejects_unsupported_capture_contract(self):
        result = module.handler(
            self._event(
                "POST",
                "/v1/producer-training/sessions/uploads",
                {
                    "session_id": "session-1",
                    "size_bytes": 10,
                    "sha256": "a" * 64,
                    "schema_version": "v3",
                    "consent_version": "consent-v1",
                    "feature_extractor_version": "features-v1",
                    "segmentation_version": "segments-v1",
                    "media_manifest": [],
                },
            ),
            object(),
        )
        self.assertEqual(result["statusCode"], 400)

    def test_requires_authentication(self):
        module.extract_claims_from_event = lambda _event: {}
        result = module.handler(
            self._event("POST", "/v1/producer-training/sessions/uploads"),
            object(),
        )
        self.assertEqual(result["statusCode"], 401)


if __name__ == "__main__":
    unittest.main()
