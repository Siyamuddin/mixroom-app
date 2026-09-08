import unittest
from unittest import mock

import support  # noqa: F401
from src.common import collaboration_repository as collaboration_module
from src.common.collaboration_repository import CollaborationRepository


class CollaborationRepositoryTests(unittest.TestCase):
    def setUp(self):
        # Existing fixtures model membership reads with list_memberships.
        patch = mock.patch.object(CollaborationRepository, '_consistent_memberships',
            lambda repo, organization_id: repo.list_memberships(organization_id=organization_id))
        patch.start()
        self.addCleanup(patch.stop)

    def test_list_memberships_filters_non_membership_entities_for_user_queries(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository._list_by_index = lambda *args, **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "user-1",
            },
            {
                "entity_type": "workspace",
                "workspace_id": "ws-1",
                "user_id": "user-1",
            },
        ]

        memberships = repository.list_memberships(user_id="user-1")

        self.assertEqual(len(memberships), 1)
        self.assertEqual(memberships[0]["entity_type"], "membership")

    def test_build_user_access_snapshot_respects_shared_workspace_disable_and_private_defaults(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "user-2",
                "role": "member",
                "status": "active",
            }
        ]
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": "Private Team",
            "status": "active",
            "shared_workspace_enabled": False,
        }
        repository.list_workspaces = lambda **kwargs: [
            {
                "entity_type": "workspace",
                "workspace_id": "ws-private",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "name": "Founder Workspace",
                "status": "active",
                "visibility": "organization",
                "default_project_privacy": "private",
            },
            {
                "entity_type": "workspace",
                "workspace_id": "ws-owned",
                "organization_id": "org-1",
                "user_id": "user-2",
                "name": "My Workspace",
                "status": "active",
                "visibility": "private",
                "default_project_privacy": "private",
            },
        ]

        def list_cloud_projects(**kwargs):
            workspace_id = kwargs.get("workspace_id")
            if workspace_id == "ws-private":
                return [
                    {
                        "entity_type": "cloud_project",
                        "project_id": "cp-hidden",
                        "workspace_id": "ws-private",
                        "user_id": "owner-1",
                        "name": "Secret Mix",
                        "status": "active",
                    }
                ]
            if workspace_id == "ws-owned":
                return [
                    {
                        "entity_type": "cloud_project",
                        "project_id": "cp-owned",
                        "workspace_id": "ws-owned",
                        "user_id": "user-2",
                        "name": "My Draft",
                        "status": "active",
                    }
                ]
            return []

        repository.list_cloud_projects = list_cloud_projects
        repository.list_owned_cloud_projects = lambda user_id: []

        snapshot = repository.build_user_access_snapshot("user-2")

        self.assertEqual(
            [workspace["workspace_id"] for workspace in snapshot["workspaces"]],
            ["ws-owned"],
        )
        self.assertEqual(
            [project["project_id"] for project in snapshot["cloud_projects"]],
            ["cp-owned"],
        )
        self.assertEqual(snapshot["summary"]["workspace_count"], 1)
        self.assertEqual(snapshot["summary"]["cloud_project_count"], 1)

    def test_build_user_access_snapshot_upgrades_education_class_cloud(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "edu-1",
                "user_id": "student-1",
                "role": "student",
                "status": "active",
            }
        ]
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": "Academy",
            "plan_code": "education",
            "status": "active",
            "shared_workspace_enabled": False,
        }
        repository.list_workspaces = lambda **kwargs: [
            {
                "entity_type": "workspace",
                "workspace_id": "edu-1-classroom",
                "organization_id": "edu-1",
                "visibility": "organization",
                "status": "active",
            }
        ]
        repository.list_cloud_projects = lambda **kwargs: [
            {
                "entity_type": "cloud_project",
                "project_id": "class-project",
                "workspace_id": "edu-1-classroom",
                "organization_id": "edu-1",
                "user_id": "student-1",
                "status": "active",
            }
        ]
        repository.list_owned_cloud_projects = lambda user_id: []
        repository.cloud_project_storage_usage = lambda user_id: {
            "project_count": 0,
            "used_bytes": 0,
        }

        repository.save_organization = mock.Mock(return_value={"shared_workspace_enabled": True})
        snapshot = repository.build_user_access_snapshot("student-1")

        self.assertEqual(snapshot["organizations"][0]["plan_code"], "education")
        self.assertEqual(snapshot["workspaces"][0]["workspace_id"], "edu-1-classroom")
        self.assertEqual(snapshot["cloud_projects"][0]["project_id"], "class-project")
        self.assertEqual(snapshot["summary"]["workspace_count"], 1)
        repository.save_organization.assert_called_once_with({
            "organization_id": "edu-1", "shared_workspace_enabled": True,
        })

    def test_build_user_access_snapshot_hides_private_project_for_non_owner(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "user-2",
                "role": "member",
                "status": "active",
            }
        ]
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": "Shared Team",
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_workspaces = lambda **kwargs: [
            {
                "entity_type": "workspace",
                "workspace_id": "ws-shared",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "name": "Shared Workspace",
                "status": "active",
                "visibility": "organization",
                "default_project_privacy": "private",
            }
        ]
        repository.list_cloud_projects = lambda **kwargs: [
            {
                "entity_type": "cloud_project",
                "project_id": "cp-private",
                "workspace_id": "ws-shared",
                "user_id": "owner-1",
                "name": "Private Draft",
                "status": "active",
            },
            {
                "entity_type": "cloud_project",
                "project_id": "cp-visible",
                "workspace_id": "ws-shared",
                "user_id": "",
                "name": "Team Mix",
                "status": "active",
            },
        ]
        repository.list_owned_cloud_projects = lambda user_id: []

        snapshot = repository.build_user_access_snapshot("user-2")

        self.assertEqual(
            [project["project_id"] for project in snapshot["cloud_projects"]],
            ["cp-visible"],
        )

    def test_get_user_cloud_project_returns_document_and_write_access(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository._s3 = mock.Mock()
        repository._s3.get_object.return_value = {
            "Body": mock.Mock(read=mock.Mock(return_value=b'{"tracks":["vox"]}'))
        }
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "user_id": "user-1",
            "name": "Mix 01",
            "status": "active",
            "document_revision": 4,
            "document_bucket": "bucket-1",
            "document_key": "cloud-projects/cp-1/latest.json",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "user-1",
            "status": "active",
            "visibility": "private",
            "default_project_privacy": "private",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": False,
        }
        repository.list_memberships = lambda **kwargs: []

        project = repository.get_user_cloud_project("user-1", "cp-1")

        self.assertTrue(project["can_write"])
        self.assertEqual(project["document"]["tracks"], ["vox"])

    def test_workspace_member_can_write_shared_cloud_project(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "workspace",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "user-2",
                "role": "member",
                "status": "active",
            }
        ]

        context = repository._cloud_project_access_context("user-2", "cp-1")

        self.assertTrue(context["can_write"])

    def test_non_member_cannot_access_workspace_project_by_id(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "workspace",
            "document_bucket": "bucket-1",
            "document_key": "workspaces/ws-1/projects/cp-1/latest.mixroom",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: []

        with self.assertRaises(FileNotFoundError):
            repository.get_cloud_project_download_url("stranger-1", "cp-1")

    def test_workspace_member_cannot_access_private_project_owned_by_another_user(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "private",
            "document_bucket": "bucket-1",
            "document_key": "workspaces/ws-1/projects/cp-1/latest.mixroom",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "member-1",
                "role": "member",
                "status": "active",
            }
        ]

        with self.assertRaises(FileNotFoundError):
            repository.get_cloud_project_download_url("member-1", "cp-1")

    def test_workspace_member_cannot_delete_another_members_project(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository.get_cloud_project = lambda project_id: {
            "entity_id": "cloud_project#cp-1",
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "workspace",
            "document_bucket": "bucket-1",
            "document_key": "workspaces/ws-1/projects/cp-1/latest.mixroom",
            "storage_mode": "blob_mixroom",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "member-1",
                "role": "member",
                "status": "active",
            }
        ]

        with self.assertRaisesRegex(PermissionError, "Only the owner"):
            repository.delete_personal_cloud_project("member-1", "cp-1")
        repository._table.delete_item.assert_not_called()

    def test_workspace_project_id_cannot_cross_to_another_workspace(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._object_client = mock.Mock(return_value=mock.Mock())
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-2",
            "organization_id": "org-2",
            "user_id": "owner-2",
            "status": "active",
            "visibility": "workspace",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "member-1",
                "role": "member",
                "status": "active",
            }
        ]

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "bucket-1",
        ):
            with self.assertRaisesRegex(PermissionError, "another account"):
                repository.create_cloud_project_upload(
                    "member-1",
                    {
                        "project_id": "cp-1",
                        "workspace_id": "ws-1",
                        "name": "Cross workspace attempt",
                        "size_bytes": 1,
                    },
                )
        repository._table.put_item.assert_not_called()

    def test_workspace_upload_rejects_mismatched_organization_id(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._object_client = mock.Mock(return_value=mock.Mock())
        repository.get_cloud_project = lambda project_id: {}
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "member-1",
                "role": "member",
                "status": "active",
            }
        ]

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "bucket-1",
        ):
            with self.assertRaises(FileNotFoundError):
                repository.create_cloud_project_upload(
                    "member-1",
                    {
                        "project_id": "cp-1",
                        "workspace_id": "ws-1",
                        "organization_id": "org-2",
                        "name": "Wrong organization attempt",
                        "size_bytes": 1,
                    },
                )
        repository._table.put_item.assert_not_called()

    def test_locked_organization_projects_remain_visible_but_read_only(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "user-2",
                "role": "member",
                "status": "active",
            }
        ]
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": "Locked Studio",
            "status": "locked",
            "shared_workspace_enabled": True,
        }
        repository.list_workspaces = lambda **kwargs: [
            {
                "entity_type": "workspace",
                "workspace_id": "ws-1",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "status": "active",
                "visibility": "organization",
                "default_project_privacy": "workspace",
            }
        ]
        repository.list_owned_cloud_projects = lambda user_id: []
        repository.list_cloud_projects = lambda **kwargs: [
            {
                "entity_type": "cloud_project",
                "project_id": "cp-1",
                "workspace_id": "ws-1",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "status": "active",
                "visibility": "workspace",
            }
        ]

        snapshot = repository.build_user_access_snapshot("user-2")

        self.assertEqual(snapshot["organizations"][0]["access_status"], "read_only")
        self.assertFalse(snapshot["workspaces"][0]["can_write"])
        self.assertFalse(snapshot["cloud_projects"][0]["can_write"])

    def test_locked_organization_makes_owned_workspace_projects_read_only(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "role": "owner",
                "status": "active",
            }
        ]
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": "Locked Studio",
            "status": "locked",
            "shared_workspace_enabled": True,
        }
        repository.list_workspaces = lambda **kwargs: [
            {
                "entity_type": "workspace",
                "workspace_id": "ws-1",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "status": "active",
                "visibility": "organization",
                "default_project_privacy": "workspace",
            }
        ]
        repository.list_owned_cloud_projects = lambda user_id: [
            {
                "entity_type": "cloud_project",
                "project_id": "cp-1",
                "workspace_id": "ws-1",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "status": "active",
                "visibility": "workspace",
            }
        ]
        repository.list_cloud_projects = lambda **kwargs: [
            {
                "entity_type": "cloud_project",
                "project_id": "cp-1",
                "workspace_id": "ws-1",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "status": "active",
                "visibility": "workspace",
            }
        ]

        snapshot = repository.build_user_access_snapshot("owner-1")

        self.assertEqual(len(snapshot["cloud_projects"]), 1)
        self.assertFalse(snapshot["cloud_projects"][0]["can_write"])

    def test_locked_organization_rejects_new_workspace_upload(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository._object_client = mock.Mock()
        repository._object_client.return_value = mock.Mock()
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "locked",
            "shared_workspace_enabled": True,
        }

        with mock.patch.object(collaboration_module.config, "CLOUD_PROJECT_DOCUMENTS_BUCKET", "bucket"):
            with self.assertRaisesRegex(PermissionError, "read-only"):
                repository.create_cloud_project_upload(
                    "owner-1",
                    {
                        "workspace_id": "ws-1",
                        "local_project_id": "local-1",
                        "name": "Mix",
                        "size_bytes": 12,
                    },
                )

    def test_same_name_studios_do_not_share_locked_workspace_projects(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": "ws-old",
            "organization_id": "org-old",
            "user_id": "owner-old",
            "status": "active",
            "visibility": "workspace",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-old",
            "user_id": "owner-old",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": "Same Studio Name",
            "status": "locked",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-new",
                "user_id": "user-new",
                "role": "owner",
                "status": "active",
            }
        ]

        with self.assertRaises(FileNotFoundError):
            repository.get_user_cloud_project("user-new", "cp-old")

    def test_reactivate_organization_preserves_identity_and_name(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        current = {
            "entity_type": "organization",
            "organization_id": "org-1",
            "name": "Andrew Team Studio",
            "status": "locked",
            "plan_code": "studio",
            "seat_limit": 5,
            "locked_at": "2026-05-01T00:00:00+00:00",
            "retention_expires_at": "2026-08-01T00:00:00+00:00",
        }
        repository.get_organization = mock.Mock(return_value=current)
        repository.list_memberships = lambda **kwargs: []

        organization = repository.reactivate_organization("org-1")

        self.assertEqual(organization["organization_id"], "org-1")
        self.assertEqual(organization["name"], "Andrew Team Studio")
        self.assertEqual(organization["status"], "active")
        self.assertEqual(organization["locked_at"], "")
        self.assertEqual(organization["retention_expires_at"], "")
        written = repository._table.put_item.call_args.kwargs["Item"]
        self.assertEqual(written["organization_id"], "org-1")
        self.assertEqual(written["name"], "Andrew Team Studio")

    def test_sync_organization_for_subscription_uses_subscription_id_not_name(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository.list_organizations = mock.Mock(
            return_value=[
                {
                    "entity_type": "organization",
                    "organization_id": "org-old",
                    "name": "Same Studio Name",
                    "status": "locked",
                    "plan_code": "studio",
                    "seat_limit": 5,
                    "source_subscription_id": "studio-sub",
                },
                {
                    "entity_type": "organization",
                    "organization_id": "org-new",
                    "name": "Same Studio Name",
                    "status": "active",
                    "plan_code": "studio",
                    "seat_limit": 5,
                    "source_subscription_id": "other-sub",
                },
            ]
        )
        repository.save_organization = mock.Mock(
            return_value={
                "organization_id": "org-old",
                "name": "Same Studio Name",
                "status": "active",
            }
        )

        result = repository.sync_organization_for_subscription(
            {
                "subscription_id": "studio-sub",
                "provider": "paddle",
                "plan_code": "studio",
                "status": "active",
                "user_id": "owner-1",
            }
        )

        self.assertEqual(result["organization_id"], "org-old")
        payload = repository.save_organization.call_args.args[0]
        self.assertEqual(payload["organization_id"], "org-old")
        self.assertEqual(payload["name"], "Same Studio Name")
        self.assertEqual(payload["status"], "active")

    def test_update_user_cloud_project_requires_matching_revision(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        repository._s3.put_object.return_value = {"VersionId": "v-2"}
        repository.get_cloud_project = lambda project_id: {
            "entity_type": "cloud_project",
            "entity_id": "cloud_project#cp-1",
            "project_id": project_id,
            "workspace_id": "ws-1",
            "organization_id": "org-1",
            "user_id": "user-1",
            "name": "Mix 01",
            "status": "active",
            "storage_mode": "s3_json",
            "document_revision": 1,
            "created_at": "2026-04-23T00:00:00+00:00",
            "updated_at": "2026-04-23T00:00:00+00:00",
        }
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "user-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "organization_id": "org-1",
                "user_id": "user-1",
                "role": "owner",
                "status": "active",
            }
        ]

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "bucket-1",
        ):
            with self.assertRaisesRegex(ValueError, "revision conflict"):
                repository.update_user_cloud_project(
                    "user-1",
                    "cp-1",
                    {
                        "expected_revision": 0,
                        "document": {"tracks": ["vox"]},
                    },
                )

            updated = repository.update_user_cloud_project(
                "user-1",
                "cp-1",
                {
                    "expected_revision": 1,
                    "document": {"tracks": ["vox"]},
                },
            )

        self.assertEqual(updated["document_revision"], 2)
        self.assertEqual(updated["document"]["tracks"], ["vox"])
        repository._table.put_item.assert_called_once()

    def test_personal_cloud_project_upload_omits_empty_workspace_index_keys(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        repository._s3.generate_presigned_url.return_value = "https://upload.example"
        repository._get_item = lambda entity_id: {}

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "bucket-1",
        ):
            result = repository.create_personal_cloud_project_upload(
                "user-1",
                {
                    "project_id": "project-1",
                    "local_project_id": "local-1",
                    "name": "Personal Mix",
                    "size_bytes": 1234,
                },
            )

        written = repository._table.put_item.call_args.kwargs["Item"]
        self.assertNotIn("workspace_id", written)
        self.assertNotIn("organization_id", written)
        self.assertEqual(written["user_id"], "user-1")
        self.assertEqual(result["upload_url"], "https://upload.example")

    def test_workspace_cloud_project_upload_sets_shared_indexes_and_keys(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        repository._s3.generate_presigned_url.return_value = "https://upload.example"
        repository._get_item = lambda entity_id: {}
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "organization_id": "org-1",
                "user_id": "user-1",
                "role": "member",
                "status": "active",
            }
        ]

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "bucket-1",
        ):
            result = repository.create_cloud_project_upload(
                "user-1",
                {
                    "workspace_id": "ws-1",
                    "organization_id": "org-1",
                    "local_project_id": "local-1",
                    "name": "Studio Mix",
                    "size_bytes": 1234,
                },
            )

        written = repository._table.put_item.call_args.kwargs["Item"]
        params = repository._s3.generate_presigned_url.call_args.kwargs["Params"]
        self.assertEqual(written["workspace_id"], "ws-1")
        self.assertEqual(written["organization_id"], "org-1")
        self.assertEqual(written["visibility"], "workspace")
        self.assertEqual(written["user_id"], "user-1")
        self.assertTrue(written["target_document_key"].startswith("workspaces/ws-1/"))
        self.assertTrue(written["pending_upload_key"].startswith("pending-uploads/workspaces/ws-1/"))
        self.assertEqual(params["Bucket"], "bucket-1")
        self.assertEqual(params["Key"], written["pending_upload_key"])
        self.assertEqual(result["upload_url"], "https://upload.example")

    def test_workspace_cloud_project_upload_preserves_original_creator(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        repository._s3.generate_presigned_url.return_value = "https://upload.example"
        repository._get_item = lambda entity_id: (
            {
                "entity_type": "cloud_project",
                "entity_id": entity_id,
                "project_id": "cp-1",
                "workspace_id": "ws-1",
                "organization_id": "org-1",
                "user_id": "owner-1",
                "name": "Studio Mix",
                "status": "active",
                "visibility": "workspace",
                "document_revision": 2,
                "document_bucket": "bucket-1",
                "document_key": "workspaces/ws-1/projects/cp-1/latest.mixroom",
            }
            if entity_id == "cloud_project#cp-1"
            else {}
        )
        repository.get_workspace = lambda workspace_id: {
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": "org-1",
            "user_id": "owner-1",
            "status": "active",
            "visibility": "organization",
            "default_project_privacy": "workspace",
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": "org-1",
            "status": "active",
            "shared_workspace_enabled": True,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "organization_id": "org-1",
                "user_id": "member-1",
                "role": "member",
                "status": "active",
            }
        ]

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "bucket-1",
        ):
            repository.create_cloud_project_upload(
                "member-1",
                {
                    "project_id": "cp-1",
                    "workspace_id": "ws-1",
                    "organization_id": "org-1",
                    "local_project_id": "local-member-1",
                    "name": "Studio Mix",
                    "size_bytes": 1234,
                    "expected_revision": 2,
                },
            )

        written = repository._table.put_item.call_args.kwargs["Item"]
        self.assertEqual(written["user_id"], "owner-1")
        self.assertEqual(written["updated_by_user_id"], "member-1")

    def test_personal_cloud_project_upload_uses_r2_compatible_signed_put(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        repository._s3.generate_presigned_url.return_value = "https://upload.example"
        repository._get_item = lambda entity_id: {}

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_DOCUMENTS_BUCKET",
            "r2-bucket",
        ), mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_STORAGE_PROVIDER",
            "r2",
        ):
            result = repository.create_personal_cloud_project_upload(
                "user-1",
                {
                    "project_id": "project-1",
                    "local_project_id": "local-1",
                    "name": "Personal Mix",
                    "size_bytes": 1234,
                },
            )

        params = repository._s3.generate_presigned_url.call_args.kwargs["Params"]
        written = repository._table.put_item.call_args.kwargs["Item"]
        self.assertEqual(written["storage_mode"], "blob_mixroom")
        self.assertEqual(written["storage_provider"], "r2")
        self.assertNotIn("ServerSideEncryption", params)
        self.assertEqual(result["upload_headers"], {"content-type": "application/octet-stream"})

    def test_save_membership_enforces_seat_limit(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "seat_limit": 1,
        }
        repository._get_item = lambda entity_id: {}
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:user-1",
                "organization_id": "org-1",
                "user_id": "user-1",
                "status": "active",
                "seat_consumed": True,
            }
        ]

        with self.assertRaisesRegex(ValueError, "seat limit reached"):
            repository.save_membership({"organization_id": "org-1", "user_id": "user-2"})

    def test_pending_invite_reserves_education_seat(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "plan_code": "education",
            "seat_limit": 2,
        }
        repository._get_item = lambda entity_id: {}
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:user-1",
                "organization_id": "org-1",
                "user_id": "user-1",
                "status": "active",
                "seat_consumed": True,
            }
        ]

        membership = repository.save_membership(
            {
                "organization_id": "org-1",
                "email": "Student@Example.com",
                "status": "pending",
            }
        )

        self.assertEqual(membership["role"], "student")
        self.assertEqual(membership["email"], "student@example.com")
        self.assertEqual(membership["status"], "pending")
        self.assertTrue(membership["seat_consumed"])
        self.assertTrue(membership["user_id"].startswith("invite:"))
        self.assertIn("invite=", membership["invite_url"])
        self.assertIn("mixroom://education/invites/", membership["app_invite_url"])

    def test_save_membership_rejects_duplicate_reserved_student_email(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "plan_code": "education",
            "seat_limit": 20,
        }
        repository._get_item = lambda entity_id: {}
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:user-1",
                "organization_id": "org-1",
                "user_id": "user-1",
                "email": "student@example.com",
                "status": "active",
                "seat_consumed": True,
            }
        ]

        with self.assertRaisesRegex(ValueError, "already has a reserved"):
            repository.save_membership(
                {
                    "organization_id": "org-1",
                    "email": "student@example.com",
                    "status": "pending",
                }
            )

    def test_accept_invite_replaces_pending_seat_without_exceeding_limit(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        invite = {
            "entity_type": "membership",
            "entity_id": "membership#org-1:invite",
            "organization_id": "org-1",
            "user_id": "invite:abc",
            "email": "student@example.com",
            "role": "student",
            "status": "pending",
            "seat_consumed": True,
            "invite_token": "invite-token",
        }
        active = {
            "entity_type": "membership",
            "entity_id": "membership#org-1:user-1",
            "organization_id": "org-1",
            "user_id": "user-1",
            "status": "active",
            "seat_consumed": True,
        }
        repository.get_organization = lambda organization_id: {
            "entity_type": "organization",
            "organization_id": organization_id,
            "status": "active",
            "plan_code": "education",
            "seat_limit": 2,
        }
        repository._list_by_entity_type = lambda entity_type: [invite]
        repository.list_memberships = lambda **kwargs: [active, invite]
        repository._get_item = lambda entity_id: {}

        membership = repository.accept_invite(
            "invite-token",
            "student-1",
            accepted_email="student@example.com",
        )

        self.assertEqual(membership["user_id"], "student-1")
        self.assertEqual(membership["status"], "active")
        repository._table.delete_item.assert_called_once_with(
            Key={"entity_id": "membership#org-1:invite"}
        )

    def test_accept_invite_rejects_wrong_signed_in_email(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository.get_organization = mock.Mock(return_value={"organization_id": "org-1", "status": "active"})
        invite = {
            "entity_type": "membership",
            "entity_id": "membership#org-1:invite",
            "organization_id": "org-1",
            "user_id": "invite:abc",
            "email": "student@example.com",
            "role": "student",
            "status": "pending",
            "seat_consumed": True,
            "invite_token": "invite-token",
        }
        repository._list_by_entity_type = lambda entity_type: [invite]

        with self.assertRaisesRegex(PermissionError, "different email"):
            repository.accept_invite(
                "invite-token",
                "student-1",
                accepted_email="other@example.com",
            )

        repository._table.delete_item.assert_not_called()

    def test_accept_invite_clears_duplicate_invite_for_existing_member_same_email(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository.get_organization = mock.Mock(return_value={"organization_id": "org-1", "status": "active"})
        invite = {
            "entity_type": "membership",
            "entity_id": "membership#org-1:invite",
            "organization_id": "org-1",
            "user_id": "invite:abc",
            "email": "student@example.com",
            "role": "student",
            "status": "pending",
            "seat_consumed": True,
            "invite_token": "invite-token",
        }
        existing = {
            "entity_type": "membership",
            "entity_id": "membership#org-1:student-1",
            "organization_id": "org-1",
            "user_id": "student-1",
            "email": "student@example.com",
            "role": "student",
            "status": "active",
            "seat_consumed": True,
        }
        repository._list_by_entity_type = lambda entity_type: [invite]
        repository.get_membership = lambda organization_id, user_id: existing

        membership = repository.accept_invite(
            "invite-token",
            "student-1",
            accepted_email="student@example.com",
        )

        self.assertEqual(membership, existing)
        repository._table.delete_item.assert_called_once_with(
            Key={"entity_id": "membership#org-1:invite"}
        )

    def test_list_education_student_usage_summarizes_project_activity(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = object()
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:student-1",
                "organization_id": "org-1",
                "user_id": "student-1",
                "email": "student@example.com",
                "role": "student",
                "status": "active",
                "seat_consumed": True,
                "updated_at": "2026-05-01T00:00:00+00:00",
            },
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:teacher-1",
                "organization_id": "org-1",
                "user_id": "teacher-1",
                "role": "teacher",
                "status": "active",
            },
        ]
        student_projects = [
            {
                "entity_type": "cloud_project",
                "project_id": "cp-1",
                "user_id": "student-1",
                "status": "active",
                "updated_at": "2026-05-02T00:00:00+00:00",
            },
            {
                "entity_type": "cloud_project",
                "project_id": "cp-2",
                "user_id": "student-1",
                "status": "archived",
                "updated_at": "2026-05-03T00:00:00+00:00",
            },
        ]
        repository.list_cloud_projects = lambda **kwargs: []
        repository.list_owned_cloud_projects = lambda user_id: student_projects

        usage = repository.list_education_student_usage("org-1")

        self.assertEqual(len(usage), 1)
        self.assertEqual(usage[0]["email"], "student@example.com")
        self.assertEqual(usage[0]["project_count"], 1)
        self.assertEqual(
            usage[0]["last_project_updated_at"],
            "2026-05-03T00:00:00+00:00",
        )

    def test_save_organization_rejects_downgrade_below_reserved_seats(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._get_item = lambda entity_id: {
            "entity_type": "organization",
            "organization_id": "org-1",
            "name": "Academy",
            "status": "active",
            "plan_code": "education",
            "seat_limit": 20,
        }
        repository.list_memberships = lambda **kwargs: [
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:user-1",
                "organization_id": "org-1",
                "user_id": "user-1",
                "status": "active",
                "seat_consumed": True,
            },
            {
                "entity_type": "membership",
                "entity_id": "membership#org-1:invite",
                "organization_id": "org-1",
                "user_id": "invite:abc",
                "status": "pending",
                "seat_consumed": True,
            },
        ]

        with self.assertRaisesRegex(ValueError, "lower than seats currently used"):
            repository.save_organization(
                {
                    "organization_id": "org-1",
                    "plan_code": "education",
                    "seat_limit": 1,
                }
            )

    def test_provision_education_organization_creates_teacher_and_class_cloud(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository.save_organization = mock.Mock(
            return_value={
                "entity_type": "organization",
                "organization_id": "edu-1",
                "name": "Academy",
                "plan_code": "education",
                "seat_limit": 73,
            }
        )
        repository.save_membership = mock.Mock(
            return_value={
                "entity_type": "membership",
                "organization_id": "edu-1",
                "user_id": "teacher-1",
                "role": "teacher",
                "status": "active",
                "seat_consumed": False,
            }
        )
        repository.list_workspaces = mock.Mock(return_value=[])
        repository.save_workspace = mock.Mock(return_value={"workspace_id": "education-cloud-edu-1"})
        repository.get_organization = mock.Mock(
            return_value={
                "entity_type": "organization",
                "organization_id": "edu-1",
                "name": "Academy",
                "plan_code": "education",
                "seat_limit": 73,
                "seats_used": 0,
            }
        )

        payload = repository.provision_education_organization(
            {
                "organization_id": "edu-1",
                "name": "Academy",
                "seat_limit": 73,
                "teacher_user_id": "teacher-1",
                "teacher_email": "Teacher@Example.com",
            },
            updated_by_user_id="admin-1",
            updated_by_email="andrew@mixroom.ai",
        )

        self.assertEqual(payload["organization"]["plan_code"], "education")
        repository.save_organization.assert_called_once()
        organization_payload = repository.save_organization.call_args.args[0]
        self.assertTrue(organization_payload["shared_workspace_enabled"])
        self.assertEqual(organization_payload["seat_limit"], 73)
        membership_payload = repository.save_membership.call_args.args[0]
        self.assertEqual(membership_payload["role"], "teacher")
        self.assertFalse(membership_payload["seat_consumed"])
        self.assertEqual(membership_payload["email"], "teacher@example.com")
        repository.save_workspace.assert_called_once()
        self.assertEqual(payload["workspace"]["workspace_id"], "education-cloud-edu-1")

    def test_provision_education_rejects_invalid_counts_before_writing(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository.save_organization = mock.Mock()
        for count in (0, -1, 1.5, True, "abc", "", None):
            with self.subTest(count=count), self.assertRaisesRegex(ValueError, "positive whole number"):
                repository.provision_education_organization({
                    "seat_limit": count, "teacher_user_id": "teacher-1",
                })
        repository.save_organization.assert_not_called()

    def test_delete_personal_cloud_project_removes_versioned_s3_objects(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        paginator = mock.Mock()
        paginator.paginate.return_value = [
            {
                "Versions": [
                    {
                        "Key": "users/user-1/projects/cp-1/latest.mixroom",
                        "VersionId": "v-1",
                    },
                    {
                        "Key": "users/user-1/projects/cp-1/latest.mixroom-extra",
                        "VersionId": "skip",
                    },
                ],
                "DeleteMarkers": [
                    {
                        "Key": "users/user-1/projects/cp-1/latest.mixroom",
                        "VersionId": "marker-1",
                    }
                ],
            }
        ]
        repository._s3.get_paginator.return_value = paginator
        repository._cloud_project_access_context = lambda user_id, project_id: {
            "can_write": True,
            "project": {
                "entity_id": "cloud_project#cp-1",
                "project_id": project_id,
                "user_id": user_id,
                "storage_mode": "s3_mixroom",
                "document_bucket": "bucket-1",
                "document_key": "users/user-1/projects/cp-1/latest.mixroom",
            },
        }

        repository.delete_personal_cloud_project("user-1", "cp-1")

        repository._s3.delete_objects.assert_called_once_with(
            Bucket="bucket-1",
            Delete={
                "Objects": [
                    {
                        "Key": "users/user-1/projects/cp-1/latest.mixroom",
                        "VersionId": "v-1",
                    },
                    {
                        "Key": "users/user-1/projects/cp-1/latest.mixroom",
                        "VersionId": "marker-1",
                    },
                ],
                "Quiet": True,
            },
        )
        repository._s3.delete_object.assert_not_called()
        repository._table.delete_item.assert_called_once_with(
            Key={"entity_id": "cloud_project#cp-1"}
        )

    def test_delete_personal_cloud_project_uses_single_delete_for_r2(self):
        repository = CollaborationRepository.__new__(CollaborationRepository)
        repository._table = mock.Mock()
        repository._s3 = mock.Mock()
        repository._cloud_project_access_context = lambda user_id, project_id: {
            "can_write": True,
            "project": {
                "entity_id": "cloud_project#cp-1",
                "project_id": project_id,
                "user_id": user_id,
                "storage_mode": "s3_mixroom",
                "document_bucket": "bucket-1",
                "document_key": "users/user-1/projects/cp-1/latest.mixroom",
            },
        }

        with mock.patch.object(
            collaboration_module.config,
            "CLOUD_PROJECT_STORAGE_PROVIDER",
            "r2",
        ):
            repository.delete_personal_cloud_project("user-1", "cp-1")

        repository._s3.get_paginator.assert_not_called()
        repository._s3.delete_object.assert_called_once_with(
            Bucket="bucket-1",
            Key="users/user-1/projects/cp-1/latest.mixroom",
        )
        repository._table.delete_item.assert_called_once_with(
            Key={"entity_id": "cloud_project#cp-1"}
        )


if __name__ == "__main__":
    unittest.main()
