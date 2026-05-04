import importlib
import unittest
from unittest import mock

from support import FakeBillingRepo, decode_json_response
from src.common.billing_catalog import default_catalog

module = importlib.import_module("src.handlers.api_entitlements")


class ApiEntitlementsTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.original_repo = module.repo
        self.original_catalog_repo = module.catalog_repo
        self.original_collaboration_repo = module.collaboration_repo
        self.original_extract_user_id = module.extract_user_id_from_event
        module.repo = self.repo
        module.catalog_repo = mock.Mock()
        module.catalog_repo.get_catalog.return_value = default_catalog()
        module.collaboration_repo = mock.Mock()
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [],
            "memberships": [],
            "workspaces": [],
            "cloud_projects": [],
            "summary": {
                "organization_count": 0,
                "workspace_count": 0,
                "cloud_project_count": 0,
            },
        }
        module.extract_user_id_from_event = lambda event: "user-1"

    def tearDown(self):
        module.repo = self.original_repo
        module.catalog_repo = self.original_catalog_repo
        module.collaboration_repo = self.original_collaboration_repo
        module.extract_user_id_from_event = self.original_extract_user_id

    def test_seeds_free_entitlement_when_missing(self):
        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["user_id"], "user-1")
        self.assertEqual(payload["tier"], "free")
        self.assertEqual(payload["plan_code"], "free")
        self.assertEqual(payload["workspace_access_summary"]["organization_count"], 0)
        self.assertEqual(self.repo.get_entitlement("user-1")["source_subscription_id"], "free-default")

    def test_normalizes_inactive_entitlement_capabilities(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "tier": "pro",
                "status": "expired",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "expires_at": "2026-03-10T00:00:00+00:00",
                "source_provider": "apple",
                "source_subscription_id": "sub-1",
                "capabilities": {"pro_editor": True},
                "management_channel": "apple",
                "revision": 3,
            }
        )

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["status"], "expired")
        self.assertFalse(payload["capabilities"]["pro_editor"])
        self.assertEqual(payload["source_provider"], "apple")
        self.assertEqual(payload["plan_code"], "producer")

    def test_merges_active_organization_access_into_effective_capabilities(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "tier": "free",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "source_provider": "admin_grant",
                "source_subscription_id": "free-default",
                "capabilities": {"video_projects": True},
                "management_channel": "free",
                "revision": 1,
            }
        )
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-1",
                    "name": "Studio Team",
                    "status": "active",
                    "membership_status": "active",
                    "membership_role": "owner",
                    "plan_code": "studio",
                }
            ],
            "memberships": [{"organization_id": "org-1", "user_id": "user-1"}],
            "workspaces": [{"workspace_id": "ws-1"}],
            "cloud_projects": [{"project_id": "cp-1"}],
            "summary": {
                "organization_count": 1,
                "workspace_count": 1,
                "cloud_project_count": 1,
            },
        }

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["capabilities"]["cloud_projects"])
        self.assertTrue(payload["capabilities"]["team_workspaces"])
        self.assertEqual(payload["workspace_access_summary"]["workspace_count"], 1)
        self.assertEqual(payload["organizations"][0]["organization_id"], "org-1")
        self.assertEqual(payload["access_sources"][1]["source_type"], "organization")

    def test_unauthorized_without_user(self):
        module.extract_user_id_from_event = lambda event: ""

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 401)

    def test_internal_error_returns_500(self):
        broken_repo = mock.Mock()
        broken_repo.get_entitlement.side_effect = RuntimeError("ddb failed")
        module.repo = broken_repo

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 500)
        self.assertIn("Internal server error", response["body"])


if __name__ == "__main__":
    unittest.main()
