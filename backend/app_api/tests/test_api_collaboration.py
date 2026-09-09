import importlib
import unittest
from unittest import mock

from support import decode_json_response

module = importlib.import_module("src.handlers.api_collaboration")


class CollaborationApiTests(unittest.TestCase):
    def setUp(self):
        self.original_repo = module.repo
        self.original_billing_repo = module.billing_repo
        self.original_catalog_repo = module.catalog_repo
        self.original_extract_user_id = module.extract_user_id_from_event
        self.original_send_auth_email = module.send_auth_email
        module.repo = mock.Mock()
        module.billing_repo = mock.Mock()
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "producer",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": 10, "storage_gb": 20},
        }
        module.billing_repo.get_user_profile.side_effect = lambda user_id: {
            "user_id": user_id,
            "username": "andrew_leew" if user_id == "user-1" else "",
            "display_name": "Andrew" if user_id == "user-1" else "",
            "email": "student@example.com" if user_id == "user-1" else "",
            "email_lc": "student@example.com" if user_id == "user-1" else "",
        }
        module.catalog_repo = mock.Mock()
        module.catalog_repo.get_catalog.return_value = {
            "plans": [
                {
                    "code": "free",
                    "group": "individual",
                    "capabilities": {"cloud_projects": True},
                    "limits": {"cloud_projects": 1, "storage_gb": 0.1},
                },
                {
                    "code": "producer",
                    "group": "individual",
                    "capabilities": {"cloud_projects": True},
                    "limits": {"cloud_projects": 10, "storage_gb": 20},
                },
                {
                    "code": "studio",
                    "group": "team",
                    "capabilities": {"cloud_projects": True},
                    "limits": {"cloud_projects": "custom", "shared_storage_gb": 1024},
                },
                {
                    "code": "education",
                    "group": "education",
                    "capabilities": {"cloud_projects": True},
                    "limits": {"cloud_projects": "custom", "storage_gb": 5},
                },
            ]
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-1",
                    "name": "Academy",
                    "plan_code": "education",
                    "status": "active",
                    "seat_limit": 10,
                    "membership_role": "teacher",
                    "membership_status": "active",
                }
            ],
            "memberships": [
                {
                    "organization_id": "org-1",
                    "user_id": "user-1",
                    "role": "teacher",
                    "status": "active",
                }
            ],
            "workspaces": [
                {
                    "workspace_id": "ws-1",
                    "organization_id": "org-1",
                    "name": "Shared",
                    "status": "active",
                }
            ],
            "cloud_projects": [
                {
                    "project_id": "cp-1",
                    "user_id": "user-1",
                    "name": "Mix 01",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 1024,
                }
            ],
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
        module.repo.create_personal_cloud_project_upload.return_value = {
            "project_id": "cp-1",
            "name": "Mix 01",
            "document_size_bytes": 1024,
            "upload_url": "https://s3.example/upload",
            "upload_headers": {"content-type": "application/octet-stream"},
            "can_write": True,
        }
        module.repo.create_cloud_project_upload.return_value = {
            "project_id": "cp-1",
            "name": "Mix 01",
            "document_size_bytes": 1024,
            "upload_url": "https://s3.example/upload",
            "upload_headers": {"content-type": "application/octet-stream"},
            "can_write": True,
        }
        module.repo.complete_personal_cloud_project_upload.return_value = {
            "project_id": "cp-1",
            "name": "Mix 01",
            "document_size_bytes": 1024,
            "document_revision": 3,
            "can_write": True,
        }
        module.repo.get_cloud_project_download_url.return_value = {
            "project_id": "cp-1",
            "name": "Mix 01",
            "download_url": "https://s3.example/download",
            "can_write": True,
        }
        module.repo.delete_personal_cloud_project.return_value = None
        module.repo.cloud_project_storage_usage.return_value = {
            "project_count": 1,
            "used_bytes": 1024,
        }
        module.repo.list_memberships.return_value = [
            {
                "organization_id": "org-1",
                "user_id": "user-1",
                "role": "teacher",
                "status": "active",
            }
        ]
        module.repo.list_education_student_usage.return_value = [
            {
                "organization_id": "org-1",
                "user_id": "student-1",
                "email": "student@example.com",
                "status": "active",
                "project_count": 2,
            }
        ]
        module.repo.get_organization.return_value = {
            "organization_id": "org-1",
            "name": "Academy",
            "plan_code": "education",
        }
        module.repo.save_membership.return_value = {
            "organization_id": "org-1",
            "user_id": "invite:student",
            "email": "student@example.com",
            "role": "student",
            "status": "pending",
            "seat_consumed": True,
            "invite_url": "https://www.mixroom.ai/signup?invite=invite-token",
        }
        module.repo.get_membership.return_value = {
            "organization_id": "org-1",
            "user_id": "invite:student",
            "email": "student@example.com",
            "role": "student",
            "status": "pending",
        }
        module.repo.accept_invite.return_value = {
            "organization_id": "org-1",
            "user_id": "user-1",
            "email": "student@example.com",
            "role": "student",
            "status": "active",
        }
        module.extract_user_id_from_event = lambda event: "user-1"
        module.send_auth_email = mock.Mock()

    def tearDown(self):
        module.repo = self.original_repo
        module.billing_repo = self.original_billing_repo
        module.catalog_repo = self.original_catalog_repo
        module.extract_user_id_from_event = self.original_extract_user_id
        module.send_auth_email = self.original_send_auth_email

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
        self.assertEqual(payload["organizations"][0]["admin_profiles"][0]["username"], "andrew_leew")
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
        self.assertEqual(payload["storage"]["used_bytes"], 1024)
        self.assertEqual(payload["storage"]["locations"][0]["storage_scope"], "personal")
        self.assertEqual(
            payload["cloud_projects"][0]["owner_profile"]["username"],
            "andrew_leew",
        )

    def test_team_plan_storage_is_reported_as_workspace_storage_only(self):
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "studio",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": "custom", "shared_storage_gb": 1024},
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-studio",
                    "name": "Studio",
                    "plan_code": "studio",
                    "status": "active",
                    "membership_status": "active",
                    "seat_limit": 5,
                }
            ],
            "memberships": [],
            "workspaces": [
                {
                    "workspace_id": "ws-studio",
                    "organization_id": "org-studio",
                    "name": "Studio Workspace",
                    "status": "active",
                }
            ],
            "cloud_projects": [
                {
                    "project_id": "personal-1",
                    "user_id": "user-1",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 1024,
                },
                {
                    "project_id": "studio-1",
                    "user_id": "user-1",
                    "workspace_id": "ws-studio",
                    "organization_id": "org-studio",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 2048,
                },
            ],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        storage = payload["storage"]
        self.assertEqual(storage["limit_bytes"], 107374182)
        locations = {
            item["workspace_id"]: item for item in storage.get("locations", [])
        }
        self.assertEqual(locations[""]["used_bytes"], 1024)
        self.assertEqual(locations[""]["limit_bytes"], 107374182)
        self.assertEqual(locations["ws-studio"]["used_bytes"], 2048)
        self.assertEqual(locations["ws-studio"]["limit_bytes"], 1099511627776)
        self.assertTrue(locations["ws-studio"]["can_write"])

    def test_locked_workspace_storage_is_reported_read_only(self):
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-studio",
                    "name": "Studio",
                    "plan_code": "studio",
                    "status": "locked",
                    "membership_status": "active",
                    "seat_limit": 5,
                }
            ],
            "memberships": [],
            "workspaces": [
                {
                    "workspace_id": "ws-studio",
                    "organization_id": "org-studio",
                    "name": "Studio Workspace",
                    "status": "active",
                    "can_write": False,
                }
            ],
            "cloud_projects": [
                {
                    "project_id": "studio-1",
                    "user_id": "user-1",
                    "workspace_id": "ws-studio",
                    "organization_id": "org-studio",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 2048,
                    "can_write": False,
                },
            ],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        locations = {
            item["workspace_id"]: item for item in payload["storage"].get("locations", [])
        }
        self.assertFalse(locations["ws-studio"]["can_write"])
        self.assertEqual(locations["ws-studio"]["organization_status"], "locked")
        self.assertFalse(payload["cloud_projects"][0]["can_write"])

    def test_education_student_can_select_personal_or_education_cloud(self):
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "free",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": 1, "storage_gb": 0.1},
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-edu",
                    "name": "Academy",
                    "plan_code": "education",
                    "status": "active",
                    "membership_status": "active",
                    "membership_role": "student",
                    "seat_limit": 20,
                }
            ],
            "memberships": [],
            "workspaces": [
                {
                    "workspace_id": "ws-edu",
                    "organization_id": "org-edu",
                    "name": "Academy Classroom",
                    "status": "active",
                }
            ],
            "cloud_projects": [
                {
                    "project_id": "personal-1",
                    "user_id": "user-1",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 1024,
                },
                {
                    "project_id": "edu-shared-1",
                    "user_id": "user-1",
                    "workspace_id": "ws-edu",
                    "organization_id": "org-edu",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 2048,
                },
            ],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        storage = payload["storage"]
        self.assertEqual(storage["plan_code"], "free")
        self.assertEqual(storage["limit_bytes"], 107374182)
        locations = {
            item["workspace_id"]: item for item in storage.get("locations", [])
        }
        self.assertEqual(set(locations), {"", "ws-edu"})
        self.assertEqual(locations[""]["label"], "Personal Cloud")
        self.assertEqual(locations[""]["limit_bytes"], 107374182)
        self.assertEqual(locations["ws-edu"]["label"], "Academy Cloud")
        self.assertEqual(locations["ws-edu"]["plan_code"], "education")
        self.assertEqual(locations["ws-edu"]["limit_bytes"], 5368709120)

    def test_education_teacher_does_not_receive_student_personal_storage(self):
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "free",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": 1, "storage_gb": 0.1},
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-edu",
                    "name": "Academy",
                    "plan_code": "education",
                    "status": "active",
                    "membership_status": "active",
                    "membership_role": "teacher",
                    "seat_limit": 20,
                }
            ],
            "memberships": [],
            "workspaces": [],
            "cloud_projects": [],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["storage"]["plan_code"], "free")
        self.assertEqual(payload["storage"]["limit_bytes"], 107374182)

    def test_creates_cloud_project_upload_when_quota_allows(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"project_id":"cp-1","name":"Mix 01","size_bytes":1024}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["cloud_project"]["upload_url"], "https://s3.example/upload")
        module.repo.create_cloud_project_upload.assert_called_once()

    def test_creates_workspace_cloud_project_upload_when_quota_allows(self):
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "free",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": 1, "storage_gb": 0.1},
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-1",
                    "name": "Studio",
                    "plan_code": "studio",
                    "status": "active",
                    "membership_role": "member",
                    "membership_status": "active",
                }
            ],
            "memberships": [
                {
                    "organization_id": "org-1",
                    "user_id": "user-1",
                    "role": "member",
                    "status": "active",
                }
            ],
            "workspaces": [
                {
                    "workspace_id": "ws-1",
                    "organization_id": "org-1",
                    "name": "Studio Workspace",
                    "status": "active",
                }
            ],
            "cloud_projects": [],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "POST"}},
                "body": (
                    '{"workspace_id":"ws-1","organization_id":"org-1",'
                    '"name":"Studio Mix","size_bytes":1024}'
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        module.repo.create_cloud_project_upload.assert_called_once()
        body = module.repo.create_cloud_project_upload.call_args.args[1]
        self.assertEqual(body["workspace_id"], "ws-1")
        self.assertEqual(body["organization_id"], "org-1")
        payload = decode_json_response(response)
        locations = {
            item["storage_scope"]: item
            for item in payload["storage"].get("locations", [])
        }
        self.assertEqual(locations["personal"]["plan_code"], "free")
        self.assertEqual(locations["workspace"]["plan_code"], "studio")

    def test_existing_workspace_upload_recovers_omitted_workspace_scope(self):
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "free",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": 1, "storage_gb": 0.1},
        }
        module.repo.get_user_cloud_project.return_value = {
            "project_id": "workspace-project-1",
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "can_write": True,
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-1",
                    "plan_code": "studio",
                    "status": "active",
                    "membership_role": "member",
                    "membership_status": "active",
                }
            ],
            "memberships": [],
            "workspaces": [
                {
                    "workspace_id": "ws-1",
                    "organization_id": "org-1",
                    "status": "active",
                }
            ],
            "cloud_projects": [
                {
                    "project_id": "workspace-project-1",
                    "workspace_id": "ws-1",
                    "organization_id": "org-1",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 1024,
                }
            ],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "POST"}},
                "body": (
                    '{"project_id":"workspace-project-1",'
                    '"name":"Studio Mix","size_bytes":2048}'
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        body = module.repo.create_cloud_project_upload.call_args.args[1]
        self.assertEqual(body["workspace_id"], "ws-1")
        self.assertEqual(body["organization_id"], "org-1")

    def test_cloud_project_upload_respects_storage_quota(self):
        module.billing_repo.get_entitlement.return_value = {
            "user_id": "user-1",
            "status": "active",
            "plan_code": "starter",
            "capabilities": {"cloud_projects": True},
            "limits": {"cloud_projects": 10, "storage_gb": 2},
        }
        module.repo.cloud_project_storage_usage.return_value = {
            "project_count": 1,
            "used_bytes": 20 * 1024 * 1024 * 1024,
        }
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [],
            "memberships": [],
            "workspaces": [],
            "cloud_projects": [
                {
                    "project_id": "cp-1",
                    "user_id": "user-1",
                    "storage_mode": "s3_mixroom",
                    "document_size_bytes": 20 * 1024 * 1024 * 1024,
                }
            ],
            "summary": {},
            "configurable": True,
        }

        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/me",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"project_id":"cp-2","name":"Mix 02","size_bytes":1024}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 403)

    def test_completes_cloud_project_upload(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/cp-1/complete",
                "pathParameters": {"project_id": "cp-1"},
                "requestContext": {"http": {"method": "POST"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["cloud_project"]["document_revision"], 3)
        module.repo.complete_personal_cloud_project_upload.assert_called_once_with(
            "user-1",
            "cp-1",
        )

    def test_returns_cloud_project_download_url(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/cp-1/download",
                "pathParameters": {"project_id": "cp-1"},
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["cloud_project"]["download_url"], "https://s3.example/download")

    def test_deletes_cloud_project(self):
        response = module.handler(
            {
                "rawPath": "/v1/cloud-projects/cp-1",
                "pathParameters": {"project_id": "cp-1"},
                "requestContext": {"http": {"method": "DELETE"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["deleted"])
        module.repo.delete_personal_cloud_project.assert_called_once_with(
            "user-1",
            "cp-1",
        )

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

    def test_returns_teacher_education_snapshot(self):
        response = module.handler(
            {
                "rawPath": "/v1/education/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["organizations"][0]["plan_code"], "education")
        self.assertEqual(payload["student_usage"][0]["project_count"], 2)
        module.repo.list_memberships.assert_called_once_with(organization_id="org-1")

    def test_returns_admin_organization_snapshot_for_studio(self):
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "studio-1",
                    "name": "Studio One",
                    "plan_code": "studio",
                    "status": "active",
                    "seat_limit": 5,
                    "owner_user_id": "user-1",
                    "membership_role": "owner",
                    "membership_status": "active",
                }
            ],
            "memberships": [
                {
                    "organization_id": "studio-1",
                    "user_id": "user-1",
                    "role": "owner",
                    "status": "active",
                }
            ],
            "summary": {},
            "configurable": True,
        }
        module.repo.list_memberships.return_value = [
            {
                "organization_id": "studio-1",
                "user_id": "member-1",
                "email": "member@example.com",
                "role": "member",
                "status": "active",
            }
        ]

        response = module.handler(
            {
                "rawPath": "/v1/organizations/me/admin",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["organizations"][0]["plan_code"], "studio")
        self.assertEqual(payload["memberships"][0]["email"], "member@example.com")
        module.repo.list_memberships.assert_called_once_with(organization_id="studio-1")

    def test_studio_admin_can_invite_member(self):
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "studio-1",
                    "name": "Studio One",
                    "plan_code": "studio",
                    "status": "active",
                    "seat_limit": 5,
                    "membership_role": "owner",
                    "membership_status": "active",
                }
            ],
            "memberships": [
                {
                    "organization_id": "studio-1",
                    "user_id": "user-1",
                    "role": "owner",
                    "status": "active",
                }
            ],
            "summary": {},
            "configurable": True,
        }
        module.repo.get_organization.return_value = {
            "organization_id": "studio-1",
            "name": "Studio One",
            "plan_code": "studio",
        }
        module.repo.save_membership.return_value = {
            "organization_id": "studio-1",
            "user_id": "invite:member",
            "email": "member@example.com",
            "role": "member",
            "status": "pending",
            "invite_url": "https://www.mixroom.ai/?auth=signup&invite=token",
        }

        response = module.handler(
            {
                "rawPath": "/v1/organizations/me/invites",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"studio-1","email":"member@example.com"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        saved_payload = module.repo.save_membership.call_args.args[0]
        self.assertEqual(saved_payload["role"], "member")
        self.assertEqual(saved_payload["status"], "pending")

    def test_studio_admin_can_release_member_seat(self):
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "studio-1",
                    "name": "Studio One",
                    "plan_code": "studio",
                    "status": "active",
                    "membership_role": "owner",
                    "membership_status": "active",
                }
            ],
            "memberships": [
                {
                    "organization_id": "studio-1",
                    "user_id": "user-1",
                    "role": "owner",
                    "status": "active",
                }
            ],
            "summary": {},
            "configurable": True,
        }
        module.repo.get_organization.return_value = {
            "organization_id": "studio-1",
            "plan_code": "studio",
        }
        module.repo.get_membership.return_value = {
            "organization_id": "studio-1",
            "user_id": "member-1",
            "email": "member@example.com",
            "role": "member",
            "status": "active",
        }

        response = module.handler(
            {
                "rawPath": "/v1/organizations/me/memberships",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"studio-1","user_id":"member-1","status":"inactive"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        saved_payload = module.repo.save_membership.call_args.args[0]
        self.assertEqual(saved_payload["role"], "member")
        self.assertEqual(saved_payload["status"], "inactive")
        self.assertFalse(saved_payload["seat_consumed"])

    def test_studio_admin_cannot_remove_owner_membership(self):
        module.repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "studio-1",
                    "name": "Studio One",
                    "plan_code": "studio",
                    "status": "active",
                    "membership_role": "owner",
                    "membership_status": "active",
                }
            ],
            "memberships": [
                {
                    "organization_id": "studio-1",
                    "user_id": "user-1",
                    "role": "owner",
                    "status": "active",
                }
            ],
            "summary": {},
            "configurable": True,
        }
        module.repo.get_membership.return_value = {
            "organization_id": "studio-1",
            "user_id": "owner-1",
            "role": "owner",
            "status": "active",
        }

        response = module.handler(
            {
                "rawPath": "/v1/organizations/me/memberships",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"studio-1","user_id":"owner-1","status":"removed"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 403)
        module.repo.save_membership.assert_not_called()

    def test_teacher_can_create_class_link_without_email(self):
        module.repo.education_class_link.return_value = {'invite_url': 'https://www.mixroom.ai/?invite=edu.token'}
        response = module.handler({'rawPath': '/v1/education/me/invites',
            'requestContext': {'http': {'method': 'POST'}},
            'body': '{"organization_id":"org-1","action":"class_link_create"}'}, object())
        self.assertEqual(response['statusCode'], 200)
        module.repo.education_class_link.assert_called_once_with('org-1', 'create', updated_by_user_id='user-1')
        module.send_auth_email.assert_not_called()
        module.repo.save_membership.assert_not_called()

    def test_student_cannot_manage_class_link(self):
        module.repo.build_user_access_snapshot.return_value['memberships'][0]['role'] = 'student'
        response = module.handler({'rawPath': '/v1/education/me/invites',
            'requestContext': {'http': {'method': 'POST'}},
            'body': '{"organization_id":"org-1","action":"class_link_revoke"}'}, object())
        self.assertEqual(response['statusCode'], 403)
        module.repo.education_class_link.assert_not_called()

    def test_teacher_can_invite_student(self):
        response = module.handler(
            {
                "rawPath": "/v1/education/me/invites",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"org-1","email":"student@example.com"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["membership"]["email"], "student@example.com")
        self.assertTrue(payload["email_sent"])
        module.send_auth_email.assert_called_once()
        module.repo.save_membership.assert_called_once()

    def test_teacher_locale_controls_invite_email_language(self):
        module.billing_repo.get_user_profile.side_effect = lambda user_id: {
            "user_id": user_id,
            "username": "teacher",
            "display_name": "Teacher",
            "locale_code": "ko-KR" if user_id == "user-1" else "",
        }

        response = module.handler(
            {
                "rawPath": "/v1/education/me/invites",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"org-1","email":"student@example.com"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        module.send_auth_email.assert_called_once()
        kwargs = module.send_auth_email.call_args.kwargs
        self.assertIn("초대", kwargs["subject"])
        self.assertIn("초대 코드", kwargs["html_body"])
        self.assertIn("lang=ko", kwargs["html_body"])
        self.assertIn("lang=ko", kwargs["text_body"])

    def test_non_teacher_cannot_invite_student(self):
        module.repo.build_user_access_snapshot.return_value["memberships"] = [
            {
                "organization_id": "org-1",
                "user_id": "user-1",
                "role": "student",
                "status": "active",
            }
        ]

        response = module.handler(
            {
                "rawPath": "/v1/education/me/invites",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"org-1","email":"student@example.com"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 403)

    def test_teacher_can_release_student_seat(self):
        response = module.handler(
            {
                "rawPath": "/v1/education/me/memberships",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"org-1","user_id":"invite:student","status":"revoked"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        module.repo.save_membership.assert_called_once()
        saved_payload = module.repo.save_membership.call_args.args[0]
        self.assertEqual(saved_payload["role"], "student")
        self.assertFalse(saved_payload["seat_consumed"])

    def test_teacher_cannot_mutate_non_student_membership(self):
        module.repo.get_membership.return_value = {
            "organization_id": "org-1",
            "user_id": "teacher-2",
            "role": "teacher",
            "status": "active",
        }

        response = module.handler(
            {
                "rawPath": "/v1/education/me/memberships",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"organization_id":"org-1","user_id":"teacher-2","status":"removed"}',
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 403)
        module.repo.save_membership.assert_not_called()

    def test_accepts_education_invite(self):
        response = module.handler(
            {
                "rawPath": "/v1/education/invites/invite-token/accept",
                "pathParameters": {"invite_token": "invite-token"},
                "requestContext": {"http": {"method": "POST"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["membership"]["status"], "active")
        module.repo.accept_invite.assert_called_once_with(
            "invite-token",
            "user-1",
            accepted_email="student@example.com",
            updated_by_user_id="user-1",
        )


if __name__ == "__main__":
    unittest.main()
