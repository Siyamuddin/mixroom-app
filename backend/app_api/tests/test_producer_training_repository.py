import base64
import io
import json
import unittest

import support  # noqa: F401

from common import config
from common.producer_training_repository import (
    ProducerTrainingRepository,
    _validate_bundle_document,
)


class _S3:
    def __init__(self):
        self.calls = []

    def generate_presigned_url(self, operation, **kwargs):
        self.calls.append((operation, kwargs))
        return "https://signed.example/upload"

    def head_object(self, **kwargs):
        self.calls.append(("head_object", kwargs))
        return {
            "ContentLength": 42,
            "Metadata": {
                "expected-size": "42",
                "sha256": "a" * 64,
                "schema-version": "v4",
                "consent-version": "consent-v1",
                "feature-extractor-version": "features-v1",
                "segmentation-version": "segments-v1",
                "media-manifest-sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
            },
            "ChecksumSHA256": base64.b64encode(bytes.fromhex("a" * 64)).decode(),
        }

    def copy_object(self, **kwargs):
        self.calls.append(("copy_object", kwargs))

    def get_object(self, **kwargs):
        self.calls.append(("get_object", kwargs))
        document = {
            "session_id": "session-1",
            "schema_version": "v4",
            "consent_version": "consent-v1",
            "feature_extractor_version": "features-v1",
            "segmentation_version": "segments-v1",
            "media_manifest": [],
            "episodes": [],
        }
        return {"Body": io.BytesIO(json.dumps(document).encode())}

    def delete_object(self, **kwargs):
        self.calls.append(("delete_object", kwargs))

    def list_objects_v2(self, **kwargs):
        self.calls.append(("list_objects_v2", kwargs))
        return {"Contents": [{"Key": f"{kwargs['Prefix']}before.flac"}]}


class _Table:
    def __init__(self):
        self.item = None
        self.calls = []

    def get_item(self, **kwargs):
        self.calls.append(("get_item", kwargs))
        return {"Item": self.item} if self.item else {}

    def put_item(self, **kwargs):
        self.calls.append(("put_item", kwargs))
        self.item = kwargs["Item"]

    def update_item(self, **kwargs):
        self.calls.append(("update_item", kwargs))


class ProducerTrainingRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.original_bucket = config.PRODUCER_TRAINING_BUCKET
        self.original_table = config.PRODUCER_TRAINING_SESSIONS_TABLE
        config.PRODUCER_TRAINING_BUCKET = "training-bucket"
        config.PRODUCER_TRAINING_SESSIONS_TABLE = "training-sessions"
        self.repo = ProducerTrainingRepository()
        self.s3 = _S3()
        self.table = _Table()
        self.repo._s3 = self.s3
        self.repo._table = self.table

    def tearDown(self):
        config.PRODUCER_TRAINING_BUCKET = self.original_bucket
        config.PRODUCER_TRAINING_SESSIONS_TABLE = self.original_table

    def test_reservation_binds_size_checksum_consent_and_encryption(self):
        result = self.repo.reserve_upload(
            user_id="producer-1",
            session_id="session-1",
            size_bytes=42,
            checksum="a" * 64,
            schema_version="v4",
            consent_version="consent-v1",
            feature_extractor_version="features-v1",
            segmentation_version="segments-v1",
            media_manifest=[],
        )
        self.assertEqual(result["expires_in_seconds"], 900)
        self.assertEqual(
            result["upload_headers"]["x-amz-server-side-encryption"], "AES256"
        )
        params = self.s3.calls[0][1]["Params"]
        self.assertEqual(params["Metadata"]["expected-size"], "42")

    def test_completion_verifies_and_promotes_pending_object(self):
        result = self.repo.complete_upload(
            user_id="producer-1",
            session_id="session-1",
            size_bytes=42,
            checksum="a" * 64,
            schema_version="v4",
            consent_version="consent-v1",
            feature_extractor_version="features-v1",
            segmentation_version="segments-v1",
            media_manifest=[],
        )
        self.assertTrue(result["accepted"])
        operations = [call[0] for call in self.s3.calls]
        self.assertEqual(
            operations,
            ["head_object", "get_object", "copy_object", "delete_object"],
        )

    def test_duplicate_completion_returns_existing_verified_object(self):
        original_head = self.s3.head_object
        calls = 0

        def head(**kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise RuntimeError("pending object was already promoted")
            return original_head(**kwargs)

        self.s3.head_object = head
        result = self.repo.complete_upload(
            user_id="producer-1",
            session_id="session-1",
            size_bytes=42,
            checksum="a" * 64,
            schema_version="v4",
            consent_version="consent-v1",
            feature_extractor_version="features-v1",
            segmentation_version="segments-v1",
            media_manifest=[],
        )
        self.assertTrue(result["accepted"])
        self.assertTrue(result["already_completed"])
        operations = [call[0] for call in self.s3.calls]
        self.assertNotIn("copy_object", operations)

    def test_delete_removes_structured_pending_and_media_objects(self):
        count = self.repo.delete_session(
            user_id="producer-1", session_id="session-1"
        )
        self.assertEqual(count, 3)
        delete_calls = [call for call in self.s3.calls if call[0] == "delete_object"]
        self.assertEqual(len(delete_calls), 3)

    def test_server_rejects_identifiers_and_local_paths_in_bundle(self):
        document = {
            "session_id": "session-1",
            "schema_version": "v4",
            "consent_version": "consent-v1",
            "feature_extractor_version": "features-v1",
            "segmentation_version": "segments-v1",
            "media_manifest": [],
            "episodes": [{"source_path": "/Users/person/client.wav"}],
        }
        with self.assertRaisesRegex(ValueError, "forbidden identifier"):
            _validate_bundle_document(
                json.dumps(document).encode(),
                session_id="session-1",
                schema_version="v4",
                consent_version="consent-v1",
                feature_extractor_version="features-v1",
                segmentation_version="segments-v1",
                media_manifest=[],
            )


if __name__ == "__main__":
    unittest.main()
