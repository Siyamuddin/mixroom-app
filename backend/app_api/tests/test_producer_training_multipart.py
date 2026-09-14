import base64
import hashlib
import io
import json
import unittest
from unittest.mock import patch, Mock
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import support  # noqa: F401
from common.producer_training_repository import (
    ProducerTrainingRepository,
    PART_SIZE,
    _user_hash,
)
from common.producer_training_stream import validate_stream


def b64(data):
    return base64.b64encode(hashlib.sha256(data).digest()).decode()


class Missing(Exception):
    def __init__(self, code):
        self.response = {"Error": {"Code": code}}


class Table:
    def __init__(self):
        self.item = None

    def get_item(self, **kwargs):
        return {"Item": self.item} if self.item else {}

    def put_item(self, **kwargs):
        self.item = kwargs["Item"]

    def update_item(self, **kwargs):
        values = kwargs["ExpressionAttributeValues"]
        condition = kwargs.get("ConditionExpression", "")
        if "attribute_exists(session_id)" in condition and (
            not self.item or self.item.get("status") in ("verified", "deleted")
        ):
            raise Missing("ConditionalCheckFailedException")
        if "attribute_not_exists(deleted_at)" in condition and self.item.get(
            "deleted_at"
        ):
            raise Missing("ConditionalCheckFailedException")
        self.item["status"] = values[":status"]
        if ":now" in values:
            self.item["updated_at"] = values[":now"]
        if ":deleted_at" in values:
            self.item["deleted_at"] = values[":deleted_at"]


class S3:
    def __init__(self):
        self.objects = {}
        self.parts = {}
        self.creates = 0
        self.completed = 0
        self.aborted = []
        self.metadata = None
        self.active = False

    def create_multipart_upload(self, **kwargs):
        self.creates += 1
        self.active = True
        self.metadata = kwargs["Metadata"]
        return {"UploadId": "upload-1"}

    def list_parts(self, **kwargs):
        if not self.active:
            raise Missing("NoSuchUpload")
        return {
            "Parts": [
                {
                    "PartNumber": n,
                    "Size": len(b),
                    "ETag": f"etag-{n}",
                    "ChecksumSHA256": b64(b),
                }
                for n, b in sorted(self.parts.items())
            ]
        }

    def generate_presigned_url(self, operation, **kwargs):
        return f'https://storage.test/{kwargs["Params"]["PartNumber"]}'

    def complete_multipart_upload(self, **kwargs):
        self.completed += 1
        self.active = False
        self.objects[kwargs["Key"]] = b"".join(
            self.parts[n] for n in sorted(self.parts)
        )

    def head_object(self, **kwargs):
        if kwargs["Key"] not in self.objects:
            raise Missing("NoSuchKey")
        return {
            "ContentLength": len(self.objects[kwargs["Key"]]),
            "Metadata": self.metadata,
            "ChecksumSHA256": "composite-checksum-4",
        }

    def get_object(self, **kwargs):
        return {"Body": io.BytesIO(self.objects[kwargs["Key"]])}

    def copy_object(self, **kwargs):
        self.objects[kwargs["Key"]] = self.objects[kwargs["CopySource"]["Key"]]

    def delete_object(self, **kwargs):
        self.objects.pop(kwargs["Key"], None)

    def abort_multipart_upload(self, **kwargs):
        self.aborted.append(kwargs["UploadId"])
        self.active = False

    def list_objects_v2(self, **kwargs):
        return {"Contents": []}


class MultipartTests(unittest.TestCase):
    def setUp(self):
        self.repo = ProducerTrainingRepository.__new__(ProducerTrainingRepository)
        self.repo._bucket = "test"
        self.repo._s3 = S3()
        self.repo._table = Table()
        self.expected = dict(
            session_id="session-1",
            schema_version="producer_training_capture_v4",
            consent_version="consent-1",
            feature_extractor_version="features-1",
            segmentation_version="segments-1",
        )

    def test_large_upload_resumes_parts_and_preserves_exact_training_json(self):
        document = {
            **self.expected,
            "media_manifest": [],
            "episodes": [],
            "notes": "a" * 26000000,
        }
        raw = json.dumps(document).encode()
        chunks = [raw[i : i + PART_SIZE] for i in range(0, len(raw), PART_SIZE)]
        fields = dict(
            user_id="producer",
            size_bytes=len(raw),
            checksum=hashlib.sha256(raw).hexdigest(),
            media_manifest=[],
            **self.expected,
        )
        checksums = [hashlib.sha256(b).hexdigest() for b in chunks]
        reserved = self.repo.reserve_upload(**fields, part_checksums=checksums)
        self.assertEqual(len(reserved["parts"]), 4)
        self.repo._s3.parts[1] = chunks[0]
        self.repo._s3.parts[2] = chunks[1]
        retry = self.repo.reserve_upload(**fields, part_checksums=checksums)
        self.assertEqual([p["part_number"] for p in retry["parts"]], [3, 4])
        self.assertEqual(self.repo._s3.creates, 1)
        for number, chunk in enumerate(chunks, 1):
            self.repo._s3.parts[number] = chunk
        result = self.repo.complete_upload(**fields)
        self.assertTrue(result["accepted"])
        self.assertEqual(self.repo._s3.objects[result["object_key"]], raw)
        self.assertEqual(
            json.loads(self.repo._s3.objects[result["object_key"]]), document
        )
        repeated = self.repo.reserve_upload(**fields, part_checksums=checksums)
        self.assertTrue(repeated["already_completed"])
        self.assertTrue(self.repo.complete_upload(**fields)["already_completed"])
        self.assertEqual(self.repo._s3.completed, 1)
        # Recover when S3 promotion succeeded but recording verified status failed.
        self.repo._table.item["status"] = "retry_needed"
        resumed = self.repo.reserve_upload(**fields, part_checksums=checksums)
        self.assertEqual(resumed["parts"], [])
        self.assertEqual(self.repo._s3.creates, 1)
        self.assertTrue(self.repo.complete_upload(**fields)["accepted"])

    def test_stream_validation_checks_content_identity_checksum_and_privacy(self):
        document = {**self.expected, "media_manifest": [], "episodes": []}

        def validate(d, **overrides):
            raw = json.dumps(d).encode()
            args = dict(
                checksum=hashlib.sha256(raw).hexdigest(),
                size=len(raw),
                expected=self.expected,
                media_manifest=[],
            )
            args.update(overrides)
            return validate_stream(io.BytesIO(raw), **args)

        validate(document)
        for bad in [
            {**document, "session_id": "wrong"},
            {**document, "episodes": [{"source_path": "/Users/person.wav"}]},
        ]:
            with self.assertRaises(ValueError):
                validate(bad)
        with self.assertRaisesRegex(ValueError, "checksum"):
            validate(document, checksum="a" * 64)

    def test_missing_or_corrupt_parts_cannot_complete(self):
        size = 26000000
        fields = dict(
            user_id="producer",
            size_bytes=size,
            checksum="a" * 64,
            media_manifest=[],
            **self.expected,
        )
        with self.assertRaisesRegex(ValueError, "every upload part"):
            self.repo.reserve_upload(**fields)
        self.repo.reserve_upload(**fields, part_checksums=["b" * 64] * 4)
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.repo.complete_upload(**fields)
        self.repo.delete_session(user_id="producer", session_id="session-1")
        self.assertEqual(self.repo._s3.aborted, ["upload-1"])

    def test_api_size_limit_supports_large_sessions(self):
        from handlers.api_producer_training import _validated_fields

        self.assertEqual(
            _validated_fields(
                {"session_id": "s", "sha256": "a" * 64, "size_bytes": 26000000}
            )["size_bytes"],
            26000000,
        )
        with self.assertRaises(ValueError):
            _validated_fields(
                {"session_id": "s", "sha256": "a" * 64, "size_bytes": 5000000001}
            )

    def test_verifier_timeout_retries_and_terminal_statuses_cannot_be_overwritten(self):
        self.repo._table.item = {
            "status": "verifying",
            "updated_at": (
                datetime.now(timezone.utc) - timedelta(minutes=17)
            ).isoformat(),
        }
        self.assertEqual(
            self.repo.upload_status(user_id="producer", session_id="session-1")[
                "status"
            ],
            "retry_needed",
        )
        for status in ("verified", "deleted"):
            self.repo._table.item["status"] = status
            self.assertFalse(
                self.repo.set_verification_status(
                    user_id="producer", session_id="session-1", status="failed"
                )
            )
            self.assertEqual(self.repo._table.item["status"], status)

    def test_api_dispatches_verification_and_reports_confirmed_status(self):
        from handlers import api_producer_training as api

        fields = dict(
            size_bytes=26000000, sha256="a" * 64, media_manifest=[], **self.expected
        )
        self.repo.reserve_upload(
            user_id="producer",
            checksum=fields["sha256"],
            size_bytes=fields["size_bytes"],
            media_manifest=[],
            part_checksums=["b" * 64] * 4,
            **self.expected,
        )
        event = {
            "httpMethod": "POST",
            "path": "/v1/producer-training/sessions/session-1/complete",
            "body": json.dumps(fields),
        }
        invoke = Mock()
        with patch.object(api, "repo", self.repo), patch.object(
            api, "extract_claims_from_event", return_value={"sub": "producer"}
        ), patch.object(
            api.rate_limiter, "enforce", return_value=SimpleNamespace(allowed=True)
        ), patch.dict(
            "os.environ", {"PRODUCER_TRAINING_WORKER_ARN": "worker"}
        ), patch(
            "boto3.client", return_value=invoke
        ):
            result = api.handler(event, None)
            self.assertEqual(result["statusCode"], 202)
            self.assertEqual(
                json.loads(result["body"]), {"accepted": False, "status": "verifying"}
            )
            payload = json.loads(invoke.invoke.call_args.kwargs["Payload"])
            self.assertEqual(payload["checksum"], fields["sha256"])
            self.assertEqual(invoke.invoke.call_args.kwargs["InvocationType"], "Event")
            api.handler(event, None)
            self.assertEqual(invoke.invoke.call_count, 1)
            # A conflicting completion must not disturb the reservation.
            event["body"] = json.dumps(dict(fields, sha256="c" * 64))
            self.assertEqual(api.handler(event, None)["statusCode"], 400)
            self.assertEqual(self.repo._table.item["status"], "verifying")
            self.repo._table.item["status"] = "verified"
            result = api.handler(
                dict(
                    event,
                    httpMethod="GET",
                    path="/v1/producer-training/sessions/session-1",
                ),
                None,
            )
            self.assertEqual(
                json.loads(result["body"]), {"status": "verified", "accepted": True}
            )

    def test_verifier_does_not_publish_a_deleted_session(self):
        document = {
            **self.expected,
            "media_manifest": [],
            "episodes": [],
            "notes": "a" * 26000000,
        }
        raw = json.dumps(document).encode()
        chunks = [raw[i : i + PART_SIZE] for i in range(0, len(raw), PART_SIZE)]
        fields = dict(
            user_id="producer",
            size_bytes=len(raw),
            checksum=hashlib.sha256(raw).hexdigest(),
            media_manifest=[],
            **self.expected,
        )
        self.repo.reserve_upload(
            **fields, part_checksums=[hashlib.sha256(b).hexdigest() for b in chunks]
        )
        self.repo._s3.parts = dict(enumerate(chunks, 1))
        copy = self.repo._s3.copy_object

        def deleting_copy(**kwargs):
            copy(**kwargs)
            self.repo.delete_session(user_id="producer", session_id="session-1")

        with patch.object(self.repo._s3, "copy_object", side_effect=deleting_copy):
            with self.assertRaisesRegex(ValueError, "deleted"):
                self.repo.complete_upload(**fields)
        self.assertEqual(self.repo._table.item["status"], "deleted")
        self.assertEqual(self.repo._s3.objects, {})
