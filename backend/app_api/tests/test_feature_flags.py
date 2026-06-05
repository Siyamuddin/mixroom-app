import importlib
import unittest

from support import decode_json_response

feature_flags = importlib.import_module("src.common.feature_flags")
handler_module = importlib.import_module("src.handlers.api_feature_flags")


class _FakeTable:
    def __init__(self):
        self.item = None

    def get_item(self, Key, ConsistentRead=False):
        return {"Item": self.item} if self.item else {}

    def update_item(self, Key, UpdateExpression, ExpressionAttributeValues, ReturnValues):
        self.item = {
            "flag_set_key": Key["flag_set_key"],
            "kind": ExpressionAttributeValues[":kind"],
            "payload": ExpressionAttributeValues[":payload"],
            "updated_at": ExpressionAttributeValues[":updated_at"],
            "updated_by_user_id": ExpressionAttributeValues[":updated_by_user_id"],
            "updated_by_email": ExpressionAttributeValues[":updated_by_email"],
        }
        return {"Attributes": self.item}


class FeatureFlagsRepositoryTests(unittest.TestCase):
    def test_defaults_to_no_remote_overrides(self):
        repo = feature_flags.FeatureFlagsRepository()
        repo._table = _FakeTable()

        payload = repo.get_flags()

        self.assertEqual(payload["flags"], {})
        self.assertEqual(payload["source"], "default")
        self.assertTrue(payload["configurable"])

    def test_updates_supported_flags(self):
        repo = feature_flags.FeatureFlagsRepository()
        repo._table = _FakeTable()

        payload = repo.update_flags(
            flags={
                "account_plan_billing_enabled": True,
                "subscription_enforcement_enabled": False,
                "iap_purchases_enabled": True,
                "cloud_projects_enabled": True,
            },
            updated_by_user_id="admin-1",
            updated_by_email="Admin@Example.com",
        )

        self.assertTrue(payload["flags"]["account_plan_billing_enabled"])
        self.assertFalse(payload["flags"]["subscription_enforcement_enabled"])
        self.assertTrue(payload["flags"]["iap_purchases_enabled"])
        self.assertTrue(payload["flags"]["cloud_projects_enabled"])
        self.assertEqual(payload["updated_by_email"], "admin@example.com")

    def test_rejects_unknown_flags(self):
        repo = feature_flags.FeatureFlagsRepository()
        repo._table = _FakeTable()

        with self.assertRaises(ValueError):
            repo.update_flags(
                flags={"unknown_flag": True},
                updated_by_user_id="admin-1",
                updated_by_email="admin@example.com",
            )


class FeatureFlagsHandlerTests(unittest.TestCase):
    def setUp(self):
        self.original_repo = handler_module.repo
        self.original_extract_user_id = handler_module.extract_user_id_from_event

    def tearDown(self):
        handler_module.repo = self.original_repo
        handler_module.extract_user_id_from_event = self.original_extract_user_id

    def test_returns_feature_flags_for_authenticated_user(self):
        handler_module.repo = type(
            "Repo",
            (),
            {
                "get_flags": lambda self: {
                    "flags": {"account_plan_billing_enabled": True},
                    "source": "remote",
                }
            },
        )()
        handler_module.extract_user_id_from_event = lambda event: "user-1"

        response = handler_module.handler(
            {
                "rawPath": "/v1/feature-flags",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["flags"]["account_plan_billing_enabled"])
        self.assertEqual(payload["requested_by_user_id"], "user-1")

    def test_requires_authentication(self):
        handler_module.extract_user_id_from_event = lambda event: ""

        response = handler_module.handler({}, object())

        self.assertEqual(response["statusCode"], 401)


if __name__ == "__main__":
    unittest.main()
