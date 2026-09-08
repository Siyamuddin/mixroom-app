from datetime import datetime, timezone
import unittest
from unittest import mock

import support  # noqa: F401
from common.access_period import access_period_active, normalize_access_expiry, saved_access_expiry, earliest_access_expiry
from common.collaboration_repository import CollaborationRepository, _org_allows_read, _org_allows_write


class AccessPeriodTests(unittest.TestCase):
    def test_expiry_boundary_and_legacy_records(self):
        now = datetime(2026, 9, 8, tzinfo=timezone.utc)
        self.assertTrue(access_period_active({}, now=now))
        self.assertFalse(access_period_active({'access_expires_at': now.isoformat()}, now=now))
        self.assertTrue(access_period_active({'access_expires_at': '2026-09-09T00:00:00Z'}, now=now))
        self.assertFalse(access_period_active({'access_expires_at': 'invalid'}, now=now))

    def test_validation_and_preserving_existing_expiry(self):
        now = datetime(2026, 9, 8, tzinfo=timezone.utc)
        self.assertEqual(normalize_access_expiry('2026-09-09T09:00:00+09:00', now=now), '2026-09-09T00:00:00+00:00')
        for value in ['invalid', '2026-09-09', '2026-09-07T00:00:00Z']:
            with self.assertRaises(ValueError):
                normalize_access_expiry(value, now=now)
        expired = {'access_expires_at': '2000-01-01T00:00:00Z'}
        self.assertEqual(saved_access_expiry({}, expired), expired['access_expires_at'])
        self.assertEqual(saved_access_expiry(expired, expired), expired['access_expires_at'])
        self.assertEqual(saved_access_expiry({'access_expires_at': ''}, expired), '')

    def test_student_access_cannot_outlive_class(self):
        self.assertEqual(earliest_access_expiry({'access_expires_at': '2026-09-10T00:00:00Z'}, {'access_expires_at': '2026-09-09T00:00:00Z'}), '2026-09-09T00:00:00+00:00')

    def test_expired_class_blocks_cloud_reads_and_writes(self):
        organization = {'status': 'active', 'access_expires_at': '2000-01-01T00:00:00Z'}
        self.assertFalse(_org_allows_read(organization))
        self.assertFalse(_org_allows_write(organization))

    def test_expired_invite_cannot_activate(self):
        repo = CollaborationRepository.__new__(CollaborationRepository)
        repo.get_membership_by_invite_token = mock.Mock(return_value={
            'organization_id': 'class', 'status': 'pending', 'email': 'student@example.com',
            'access_expires_at': '2000-01-01T00:00:00Z',
        })
        repo.get_organization = mock.Mock(return_value={'status': 'active'})
        repo.save_membership = mock.Mock()
        with self.assertRaisesRegex(ValueError, 'access period has ended'):
            repo.accept_invite('token', 'student', accepted_email='student@example.com')
        repo.save_membership.assert_not_called()

    def test_expired_student_membership_is_not_active(self):
        repo = CollaborationRepository.__new__(CollaborationRepository)
        repo.list_memberships = mock.Mock(return_value=[{
            'organization_id': 'class', 'status': 'active', 'access_expires_at': '2000-01-01T00:00:00Z',
        }])
        self.assertIsNone(repo._active_membership_for_org('student', 'class'))

    def test_acceptance_preserves_custom_deadline_instead_of_restarting_duration(self):
        repo = CollaborationRepository.__new__(CollaborationRepository)
        expiry = '2998-01-01T00:00:00+00:00'
        repo.get_membership_by_invite_token = mock.Mock(return_value={
            'organization_id': 'class', 'status': 'pending', 'email': 'student@example.com',
            'role': 'student', 'access_expires_at': expiry,
        })
        repo.get_organization = mock.Mock(return_value={'status': 'active', 'access_expires_at': '2999-01-01T00:00:00+00:00'})
        repo.get_membership = mock.Mock(return_value={})
        repo.save_membership = mock.Mock(return_value={})
        repo.accept_invite('token', 'student', accepted_email='student@example.com')
        self.assertEqual(repo.save_membership.call_args.args[0]['access_expires_at'], expiry)

    def test_student_can_edit_owned_class_project_only_until_membership_expires(self):
        repo = CollaborationRepository.__new__(CollaborationRepository)
        repo.get_organization = mock.Mock(return_value={'status': 'active', 'plan_code': 'education'})
        member = {'organization_id': 'class', 'role': 'student', 'status': 'active'}
        repo.list_memberships = mock.Mock(return_value=[member])
        project = {'user_id': 'student', 'organization_id': 'class'}
        self.assertTrue(repo._safe_can_write_project('student', project, {'status': 'active'}))
        member['access_expires_at'] = '2000-01-01T00:00:00Z'
        self.assertFalse(repo._safe_can_write_project('student', project, {'status': 'active'}))
