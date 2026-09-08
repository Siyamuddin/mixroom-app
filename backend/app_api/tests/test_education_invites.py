import unittest
from unittest import mock

import support  # noqa: F401
from common import education_invites as module


class EducationInvitesTests(unittest.TestCase):
    def setUp(self):
        self.repo = mock.Mock()
        self.repo.get_organization.return_value = {
            'organization_id': 'school', 'name': 'School', 'plan_code': 'education',
            'status': 'active', 'seats_available': 60,
        }
        self.members = []
        self.repo.list_memberships.side_effect = lambda **kwargs: self.members
        def save(payload, **kwargs):
            member = {**payload, 'invite_url': 'https://www.mixroom.ai/?auth=signup&invite=token', 'invite_token': 'token'}
            self.members.append(member)
            return member
        self.repo.save_membership.side_effect = save
        self.sender = mock.patch.object(module, 'send_education_invite_email', return_value=(True, ''))
        self.send = self.sender.start()
        self.addCleanup(self.sender.stop)

    def invite(self, **kwargs):
        return module.invite_education_student(self.repo, {
            'organization_id': 'school', 'email': 'student@example.com', **kwargs,
        }, admin_user_id='employee', admin_email='employee@example.com')

    def test_preview_sixty_students_does_not_write_or_email(self):
        result = module.review_education_roster(self.repo, 'school', [f'student{i}@example.com' for i in range(60)])
        self.assertTrue(result['can_send'])
        self.assertEqual(result['seats_needed'], 60)
        self.repo.save_membership.assert_not_called()
        self.send.assert_not_called()

    def test_review_deduplicates_and_classifies_existing_members(self):
        self.members.extend([
            {'email': 'active@example.com', 'role': 'student', 'status': 'active'},
            {'email': 'pending@example.com', 'role': 'student', 'status': 'pending', 'invite_url': 'link'},
            {'email': 'teacher@example.com', 'role': 'teacher', 'status': 'active'},
        ])
        result = module.review_education_roster(self.repo, 'school', [
            ' New@example.com ', 'new@example.com', 'active@example.com', 'pending@example.com', 'teacher@example.com', 'bad',
        ])
        self.assertEqual(result['duplicates'], 1)
        self.assertEqual([row['status'] for row in result['rows']], ['ready', 'already_active', 'pending', 'existing_staff', 'invalid'])
        self.assertFalse(result['can_send'])
        self.assertEqual(result['seats_needed'], 1)

    def test_capacity_checked_again_when_sending(self):
        self.repo.get_organization.return_value['seats_available'] = 0
        with self.assertRaisesRegex(ValueError, 'No student seats'):
            self.invite()
        self.repo.save_membership.assert_not_called()
        self.send.assert_not_called()

    def test_send_then_repeat_does_not_duplicate_seat_or_email(self):
        self.assertEqual(self.invite()['status'], 'sent')
        self.assertEqual(self.invite()['status'], 'pending')
        self.repo.save_membership.assert_called_once()
        self.send.assert_called_once()
        self.assertEqual(self.members[0]['role'], 'student')
        self.assertTrue(self.members[0]['seat_consumed'])

    def test_failed_delivery_resend_reuses_pending_invite_at_full_capacity(self):
        self.send.return_value = (False, 'suppressed')
        result = self.invite()
        self.assertEqual(result['status'], 'email_failed')
        self.assertTrue(result['invite_url'])
        self.repo.get_organization.return_value['seats_available'] = 0
        self.send.return_value = (True, '')
        resent = self.invite(resend=True)
        self.assertEqual(resent['status'], 'sent')
        self.assertEqual(result['invite_url'], resent['invite_url'])
        self.repo.save_membership.assert_called_once()

    def test_active_student_never_receives_invitation(self):
        self.members.append({'email': 'student@example.com', 'role': 'student', 'status': 'active'})
        self.assertEqual(self.invite(resend=True)['status'], 'already_active')
        self.send.assert_not_called()

    def test_resend_does_not_recreate_removed_invite(self):
        with self.assertRaisesRegex(ValueError, 'no longer exists'):
            self.invite(resend=True)
        self.repo.save_membership.assert_not_called()

    def test_invalid_email_or_inactive_school_cannot_send(self):
        with self.assertRaisesRegex(ValueError, 'valid student email'):
            self.invite(email='bad')
        self.repo.get_organization.return_value['status'] = 'suspended'
        with self.assertRaisesRegex(ValueError, 'Activate'):
            self.invite()
        self.send.assert_not_called()

    def test_non_education_organization_rejected(self):
        self.repo.get_organization.return_value['plan_code'] = 'studio'
        with self.assertRaisesRegex(ValueError, 'Education organization'):
            self.invite()

    def test_invalid_batch_size_rejected(self):
        for emails in ([], 'a@example.com', ['a@example.com'] * 501):
            with self.subTest(emails=type(emails)), self.assertRaises(ValueError):
                module.review_education_roster(self.repo, 'school', emails)

    def test_student_period_is_saved_and_resend_preserves_it(self):
        expiry = "2998-01-01T00:00:00+00:00"
        self.repo.get_organization.return_value["access_expires_at"] = "2999-01-01T00:00:00+00:00"
        result = self.invite(access_expires_at=expiry)
        self.assertEqual(result["access_expires_at"], expiry)
        self.assertEqual(self.members[0]["access_expires_at"], expiry)
        self.invite(resend=True, access_expires_at="2997-01-01T00:00:00+00:00")
        self.assertEqual(self.members[0]["access_expires_at"], expiry)

    def test_inherited_period_and_expired_class(self):
        self.repo.get_organization.return_value["access_expires_at"] = "2999-01-01T00:00:00+00:00"
        result = module.review_education_roster(self.repo, "school", ["a@example.com"])
        self.assertEqual(result["access_expires_at"], "2999-01-01T00:00:00+00:00")
        self.repo.get_organization.return_value["access_expires_at"] = "2000-01-01T00:00:00+00:00"
        with self.assertRaisesRegex(ValueError, "class has ended"):
            self.invite()
        self.send.assert_not_called()

    def test_student_period_after_class_is_rejected_before_writing(self):
        self.repo.get_organization.return_value["access_expires_at"] = "2998-01-01T00:00:00+00:00"
        with self.assertRaisesRegex(ValueError, "after the class"):
            self.invite(access_expires_at="2999-01-01T00:00:00+00:00")
        self.repo.save_membership.assert_not_called()
        self.send.assert_not_called()

    def test_email_template_uses_language_and_preserves_token(self):
        # Exercise the real shared sender without network delivery.
        self.sender.stop()
        delivery = mock.Mock()
        result = module.send_education_invite_email(
            membership={'email': 'a@example.com', 'invite_url': 'https://www.mixroom.ai/?auth=signup&invite=abc'},
            organization={'name': '<School>'}, locale='ko', send_email=delivery,
        )
        self.assertEqual(result, (True, ''))
        body = delivery.call_args.kwargs['html_body']
        self.assertIn('&lt;School&gt;', body)
        self.assertIn('invite=abc', body)
        self.assertIn('lang=ko', body)
