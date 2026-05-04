import importlib
import unittest
from unittest import mock

from support import decode_json_response

module = importlib.import_module("src.handlers.api_collaboration")


class CollaborationApiTests(unittest.TestCase):
    def setUp(self):
        self.original_repo = module.repo
        self.original_extract_user_id = module.extract_user_id_from_event
        module.repo = mock.Mock()
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [{"organization_id": "org-1", "name": "Team"}],
            "memberships": [{"organization_id": "org-1", "user_id": "user-1"}],
            "workspaces": [{"workspace_id": "ws-1", "name": "Shared"}],
            "cloud_projects": [{"project_id": "cp-1", "name": "Mix 01"}],
            "summary": {
                "organization_count": 1,
                "workspace_count": 1,
                "cloud_project_count": 1,
            },
            "configurable": True,
        }
        module.repo.get_user_cloud_project.return_value = {
            "project_id": "cp-1",
            "name": "Mix 01",
            "document_revision": 2,
            "document": {"tracks": []},
            "can_write": True,
        }
        module.repo.update_user_cloud_project.return_value = {
            "project_id": "cp-1",
            "name": "Mix 01",
            "document_revision": 3,
            "document": {"tracks": ["vox"]},
            "can_write": True,
        }
        module.extract_user_id_from_event = lambda event: "user-1"

    def tearDown(self):
        module.repo = self.original_repo
        module.extract_user_id_from_event = self.original_extract_user_id

    def test_returns_organizations_snapshot(self):
        response = module.handler(
            {
                "rawPath": "/v1/organizations/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["organizations"][0]["organization_id"], "org-1")
        self.assertEqual(payload["summary"]["organization_count"], 1)

    def test_returns_workspaces_snapshot(self):
        response = module.handler(
            {
                "rawPath": "/v1/workspaces/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["workspaces"][0]["workspace_id"], "ws-1")

    def test_returns_cloud_projects_snapshot(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["cloud_projects"][0]["project_id"], "cp-1")

    def test_returns_cloud_project_detail(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/cp-1",
                "pathParameters": {"project_id": "cp-1"},
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["cloud_project"]["project_id"], "cp-1")
        module.repo.get_user_cloud_project.assert_called_once_with("user-1", "cp-1")

    def test_updates_cloud_project_detail(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/cp-1",
                "pathParameters": {"project_id": "cp-1"},
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"expected_revision":2,"document":{"tracks":["vox"]}}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["cloud_project"]["document_revision"], 3)
        module.repo.update_user_cloud_project.assert_called_once()


if __name__ == "__main__":
    unittest.main()
