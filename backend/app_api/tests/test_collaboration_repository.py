import unittest
from unittest import mock

from src.common import collaboration_repository as collaboration_module
from src.common.collaboration_repository import CollaborationRepository


class CollaborationRepositoryTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
