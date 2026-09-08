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
                "plan_code": "producer",
                "status": "expired",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "expires_at": "2026-03-10T00:00:00+00:00",
                "source_provider": "apple",
                "source_subscription_id": "sub-1",
                "capabilities": {"all_plugins": True},
                "management_channel": "apple",
                "revision": 3,
            }
        )

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["status"], "active")
        self.assertFalse(payload["capabilities"]["all_plugins"])
        self.assertEqual(payload["source_provider"], "admin_grant")
        self.assertEqual(payload["tier"], "free")
        self.assertEqual(payload["plan_code"], "free")

    def test_treats_past_expiry_active_entitlement_as_free_access(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "starter",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "expires_at": "2026-03-10T00:00:00+00:00",
                "source_provider": "google",
                "source_subscription_id": "sub-1",
                "product_code": "starter_monthly",
                "capabilities": {"all_plugins": True},
                "limits": {"ai_prompts_daily": 400},
                "management_channel": "google",
                "revision": 3,
            }
        )

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["status"], "active")
        self.assertEqual(payload["plan_code"], "free")
        self.assertEqual(payload["source_provider"], "admin_grant")
        self.assertEqual(payload["source_subscription_id"], "free-default")
        self.assertEqual(payload["product_code"], "")
        self.assertEqual(payload["limits"]["ai_prompts_daily"], 100)

    def test_uses_legacy_tier_fallback_and_preserves_product_code(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "tier": "pro",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "source_provider": "google",
                "source_subscription_id": "sub-1",
                "product_code": "producer_yearly",
                "capabilities": {},
                "management_channel": "google",
                "revision": 3,
            }
        )

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["tier"], "pro")
        self.assertEqual(payload["plan_code"], "producer")
        self.assertEqual(payload["product_code"], "producer_yearly")
        personal_source = payload["access_sources"][0]
        self.assertEqual(personal_source["source_type"], "personal")
        self.assertEqual(personal_source["source_provider"], "google")
        self.assertEqual(personal_source["source_subscription_id"], "sub-1")
        self.assertEqual(personal_source["management_channel"], "google")
        self.assertEqual(personal_source["product_code"], "producer_yearly")

    def test_collaboration_snapshot_failure_does_not_break_entitlements(self):
        module.collaboration_repo.build_user_access_snapshot.side_effect = RuntimeError("ddb failed")
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "free",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "source_provider": "admin_grant",
                "source_subscription_id": "free-default",
                "capabilities": {},
                "management_channel": "free",
                "revision": 1,
            }
        )

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["plan_code"], "free")
        self.assertEqual(payload["workspace_access_summary"]["workspace_count"], 0)
        self.assertEqual(payload["organizations"], [])

    def test_merges_active_organization_access_into_effective_capabilities(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "free",
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
        self.assertEqual(float(payload["limits"]["storage_gb"]), 0.1)
        self.assertEqual(payload["limits"]["shared_storage_gb"], 1024)
        self.assertEqual(payload["workspace_access_summary"]["workspace_count"], 1)
        self.assertEqual(payload["organizations"][0]["organization_id"], "org-1")
        self.assertEqual(payload["access_sources"][1]["source_type"], "organization")
        self.assertEqual(payload["access_sources"][0]["source_type"], "personal")
        self.assertEqual(payload["access_sources"][0]["plan_code"], "free")
        self.assertEqual(payload["access_sources"][0]["source_provider"], "admin_grant")

    def test_education_student_gets_starter_like_personal_entitlement(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "free",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "source_provider": "admin_grant",
                "source_subscription_id": "free-default",
                "capabilities": {},
                "management_channel": "free",
                "revision": 1,
            }
        )
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "edu-1",
                    "name": "Academy",
                    "status": "active",
                    "membership_status": "active",
                    "membership_role": "student",
                    "plan_code": "education",
                }
            ],
            "memberships": [{"organization_id": "edu-1", "user_id": "user-1"}],
            "workspaces": [],
            "cloud_projects": [],
            "summary": {
                "organization_count": 1,
                "workspace_count": 0,
                "cloud_project_count": 0,
            },
        }

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["plan_code"], "education")
        self.assertTrue(payload["capabilities"]["all_plugins"])
        self.assertTrue(payload["capabilities"]["cloud_projects"])
        self.assertFalse(payload["capabilities"]["team_workspaces"])
        self.assertEqual(payload["limits"]["storage_gb"], 5)
        self.assertEqual(payload["limits"]["ai_prompts_daily"], 400)
        self.assertEqual(payload["access_sources"][1]["plan_code"], "education")

    def test_class_deadline_is_returned_and_expired_access_is_removed(self):
        organization = {
            "organization_id": "edu-1", "name": "Day class", "status": "active",
            "membership_status": "active", "membership_role": "student", "plan_code": "education",
            "access_expires_at": "2999-01-01T00:00:00+00:00",
        }
        module.collaboration_repo.build_user_access_snapshot.return_value["organizations"] = [organization]
        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())
        payload = decode_json_response(response)
        self.assertEqual(payload["plan_code"], "education")
        self.assertEqual(payload["expires_at"], organization["access_expires_at"])
        organization["access_expires_at"] = "2000-01-01T00:00:00+00:00"
        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())
        payload = decode_json_response(response)
        self.assertEqual(payload["plan_code"], "free")
        self.assertFalse(any(source.get("source_type") == "organization" for source in payload["access_sources"]))

    def test_education_teacher_org_is_visible_without_student_entitlement(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "free",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "source_provider": "admin_grant",
                "source_subscription_id": "free-default",
                "capabilities": {},
                "management_channel": "free",
                "revision": 1,
            }
        )
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "edu-1",
                    "name": "Academy",
                    "status": "active",
                    "membership_status": "active",
                    "membership_role": "teacher",
                    "plan_code": "education",
                }
            ],
            "memberships": [{"organization_id": "edu-1", "user_id": "user-1"}],
            "workspaces": [],
            "cloud_projects": [],
            "summary": {
                "organization_count": 1,
                "workspace_count": 0,
                "cloud_project_count": 0,
            },
        }

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["plan_code"], "free")
        self.assertFalse(payload["capabilities"]["all_plugins"])
        self.assertEqual(float(payload["limits"]["storage_gb"]), 0.1)
        self.assertEqual(payload["organizations"][0]["plan_code"], "education")
        self.assertEqual(len(payload["access_sources"]), 1)

    def test_locked_organization_is_visible_without_granting_plan_capabilities(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "free",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "source_provider": "admin_grant",
                "source_subscription_id": "free-default",
                "capabilities": {},
                "management_channel": "free",
                "revision": 1,
            }
        )
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-1",
                    "name": "Locked Studio",
                    "status": "locked",
                    "membership_status": "active",
                    "membership_role": "owner",
                    "plan_code": "studio",
                    "can_write": False,
                    "access_status": "read_only",
                }
            ],
            "memberships": [{"organization_id": "org-1", "user_id": "user-1"}],
            "workspaces": [{"workspace_id": "ws-1", "can_write": False}],
            "cloud_projects": [{"project_id": "cp-1", "can_write": False}],
            "summary": {
                "organization_count": 1,
                "workspace_count": 1,
                "cloud_project_count": 1,
            },
        }

        response = module.handler({"rawPath": "/v1/entitlements/me"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["plan_code"], "free")
        self.assertFalse(payload["capabilities"]["team_workspaces"])
        self.assertEqual(payload["organizations"][0]["status"], "locked")
        self.assertFalse(payload["organizations"][0]["can_write"])
        self.assertEqual(len(payload["access_sources"]), 1)
        self.assertEqual(payload["access_sources"][0]["source_type"], "personal")

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
