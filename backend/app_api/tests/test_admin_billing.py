import importlib
import unittest
from unittest import mock

from support import decode_json_response
from src.common.billing_catalog import default_catalog

module = importlib.import_module("src.handlers.api_admin_billing")


class AdminBillingApiTests(unittest.TestCase):
    def setUp(self):
        self.original_catalog_repo = module.catalog_repo
        self.original_feature_flags_repo = module.feature_flags_repo
        self.original_collaboration_repo = module.collaboration_repo
        self.original_access_repo = module.access_repo
        self.original_admin_identity = module._admin_identity
        module.catalog_repo = mock.Mock()
        module.catalog_repo.get_catalog.return_value = default_catalog()
        module.catalog_repo.replace_catalog.return_value = default_catalog()
        module.feature_flags_repo = mock.Mock()
        module.feature_flags_repo.get_flags.return_value = {
            "flags": {"account_plan_billing_enabled": True},
            "configurable": True,
        }
        module.feature_flags_repo.update_flags.return_value = {
            "flags": {
                "account_plan_billing_enabled": True,
                "subscription_enforcement_enabled": True,
                "iap_purchases_enabled": True,
            },
            "configurable": True,
        }
        module.collaboration_repo = mock.Mock()
        module.collaboration_repo.is_configured.return_value = True
        module.collaboration_repo.list_organizations.return_value = []
        module.collaboration_repo.list_memberships.return_value = []
        module.collaboration_repo.list_workspaces.return_value = []
        module.collaboration_repo.list_cloud_projects.return_value = []
        module.collaboration_repo.save_organization.return_value = {
            "organization_id": "org-1",
            "name": "Team",
        }
        module.collaboration_repo.provision_education_organization.return_value = {
            "organization": {
                "organization_id": "edu-1",
                "name": "School",
                "plan_code": "education",
                "seat_limit": 20,
            },
            "teacher_membership": {
                "organization_id": "edu-1",
                "user_id": "teacher-1",
                "role": "teacher",
                "status": "active",
            },
            "workspace": {
                "workspace_id": "edu-1-classroom",
                "organization_id": "edu-1",
            },
        }
        module.access_repo = mock.Mock()
        module.access_repo.is_email_allowed.return_value = True
        module._admin_identity = lambda event: ("client-1", "admin-1", "andrew@mixroom.ai")

    def tearDown(self):
        module.catalog_repo = self.original_catalog_repo
        module.feature_flags_repo = self.original_feature_flags_repo
        module.collaboration_repo = self.original_collaboration_repo
        module.access_repo = self.original_access_repo
        module._admin_identity = self.original_admin_identity

    def test_gets_billing_catalog(self):
        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/billing-catalog",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertIn("plans", payload)
        self.assertEqual(payload["requested_by"], "admin-1")

    def test_replaces_billing_catalog(self):
        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/billing-catalog",
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"plans":[],"products":[],"provider_products":[],"support":{}}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        module.catalog_repo.replace_catalog.assert_called_once()

    def test_gets_feature_flags(self):
        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/feature-flags",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["flags"]["account_plan_billing_enabled"])
        self.assertEqual(payload["requested_by"], "admin-1")

    def test_updates_feature_flags(self):
        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/feature-flags",
                "requestContext": {"http": {"method": "PUT"}},
                "body": (
                    '{"flags":{'
                    '"account_plan_billing_enabled":true,'
                    '"subscription_enforcement_enabled":true,'
                    '"iap_purchases_enabled":true'
                    "}}"
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        module.feature_flags_repo.update_flags.assert_called_once()

    def test_saves_organization(self):
        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/billing/organizations",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"name":"Team"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["organization"]["organization_id"], "org-1")

    def test_provisions_education_organization(self):
        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/billing/education-provisioning",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"name":"School","seat_limit":20,"teacher_user_id":"teacher-1"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["organization"]["plan_code"], "education")
        module.collaboration_repo.provision_education_organization.assert_called_once()

    def test_rejects_not_allowlisted_admin(self):
        module.access_repo.is_email_allowed.return_value = False

        response = module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/billing-catalog",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 403)


if __name__ == "__main__":
    unittest.main()
