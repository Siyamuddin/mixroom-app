import importlib
import unittest
from unittest import mock

from support import decode_json_response
from src.common.billing_catalog import default_catalog

module = importlib.import_module("src.handlers.api_billing_catalog")


class BillingCatalogApiTests(unittest.TestCase):
    def setUp(self):
        self.original_repo = module.repo
        self.original_extract_user_id = module.extract_user_id_from_event
        module.repo = mock.Mock()
        module.repo.get_catalog.return_value = default_catalog()
        module.extract_user_id_from_event = lambda event: "user-1"

    def tearDown(self):
        module.repo = self.original_repo
        module.extract_user_id_from_event = self.original_extract_user_id

    def test_returns_catalog_for_authorized_user(self):
        response = module.handler({"rawPath": "/v1/billing/catalog"}, object())

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertIn("plans", payload)
        self.assertEqual(payload["requested_by_user_id"], "user-1")

    def test_rejects_unauthorized_user(self):
        module.extract_user_id_from_event = lambda event: ""

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 401)

    def test_returns_500_on_repo_failure(self):
        module.repo.get_catalog.side_effect = RuntimeError("ddb failed")

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 500)


if __name__ == "__main__":
    unittest.main()
