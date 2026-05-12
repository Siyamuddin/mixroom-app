import unittest
from unittest import mock

import support  # noqa: F401
from src.common import cloud_object_storage, config


class CloudObjectStorageTests(unittest.TestCase):
    def test_create_r2_client_uses_cloudflare_endpoint_and_sigv4(self):
        with mock.patch.object(config, "CLOUD_PROJECT_STORAGE_PROVIDER", "r2"), mock.patch(
            "src.common.cloud_object_storage.load_cloud_project_r2_credentials",
            return_value={
                "access_key_id": "access-key",
                "secret_access_key": "secret-key",
                "account_id": "account-id",
                "endpoint_url": "https://account-id.r2.cloudflarestorage.com",
            },
        ), mock.patch("src.common.cloud_object_storage.boto3.client") as boto_client:
            cloud_object_storage.create_cloud_project_object_client()

        boto_client.assert_called_once()
        kwargs = boto_client.call_args.kwargs
        self.assertEqual(kwargs["service_name"], "s3")
        self.assertEqual(
            kwargs["endpoint_url"],
            "https://account-id.r2.cloudflarestorage.com",
        )
        self.assertEqual(kwargs["aws_access_key_id"], "access-key")
        self.assertEqual(kwargs["aws_secret_access_key"], "secret-key")
        self.assertEqual(kwargs["region_name"], "auto")

    def test_r2_omits_s3_managed_encryption_headers(self):
        with mock.patch.object(config, "CLOUD_PROJECT_STORAGE_PROVIDER", "r2"):
            self.assertEqual(cloud_object_storage.put_object_extra_args(), {})
            self.assertEqual(cloud_object_storage.copy_object_extra_args(), {})
            self.assertEqual(
                cloud_object_storage.upload_headers("application/octet-stream"),
                {"content-type": "application/octet-stream"},
            )
            self.assertFalse(cloud_object_storage.supports_object_versions())


if __name__ == "__main__":
    unittest.main()
