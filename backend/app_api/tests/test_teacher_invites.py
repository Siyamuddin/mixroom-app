import unittest
from unittest import mock
import support  # noqa: F401
from src.common.collaboration_repository import CollaborationRepository
from common.education_invites import send_education_invite_email, resend_teacher_invite


class TeacherInvitesTests(unittest.TestCase):
    def repository(self):
        repo = CollaborationRepository.__new__(CollaborationRepository)
        records = {}
        repo._table = mock.Mock()
        repo._table.put_item.side_effect = lambda Item: records.update({Item['entity_id']: Item})
        repo._table.delete_item.side_effect = lambda Key: records.pop(Key['entity_id'], None)
        repo._get_item = lambda key: records.get(key, {})
        repo._list_by_entity_type = lambda kind: list(records.values())
        repo.list_memberships = lambda **kwargs: list(records.values())
        repo._consistent_memberships = lambda organization_id: list(records.values())
        def transact(TransactItems):
            for operation in TransactItems:
                if 'Put' in operation:
                    item = operation['Put']['Item']
                    records[item['entity_id']] = item
                elif 'Delete' in operation:
                    records.pop(operation['Delete']['Key']['entity_id'], None)
        repo._table.meta.client.transact_write_items.side_effect = transact
        org = {'organization_id': 'school', 'name': 'School', 'plan_code': 'education',
               'status': 'active', 'seat_limit': 1, 'access_expires_at': '2099-01-01T00:00:00Z'}
        repo.get_organization = lambda key: org
        repo.save_organization = mock.Mock(return_value=org)
        repo.ensure_education_cloud_workspace = mock.Mock(return_value={'workspace_id': 'cloud'})
        return repo, records

    def test_class_workspace_omits_empty_dynamodb_user_index_key(self):
        repo, records = self.repository()
        repo.get_workspace = lambda key: {}
        workspace = repo.save_workspace({'organization_id': 'school', 'workspace_id': 'class-cloud'})
        stored = records[workspace['entity_id']]
        self.assertNotIn('user_id', stored)
        self.assertEqual(stored['organization_id'], 'school')
        repo.save_workspace({'organization_id': 'school', 'workspace_id': 'owned-cloud', 'owner_user_id': 'teacher-1'})
        self.assertEqual(records['workspace#owned-cloud']['user_id'], 'teacher-1')

    def test_email_only_teacher_can_sign_up_later_and_accept_at_full_student_capacity(self):
        repo, records = self.repository()
        records['student'] = {'entity_id': 'student', 'organization_id': 'school', 'user_id': 'student',
                              'email': 'student@example.com', 'role': 'student', 'status': 'active', 'seat_consumed': True}
        result = repo.provision_education_organization({'name': 'School', 'seat_limit': 1, 'teacher_email': 'Teacher@Example.com'})
        invite = result['teacher_membership']
        self.assertEqual(invite['status'], 'pending')
        self.assertFalse(invite['seat_consumed'])
        self.assertIn('invite=', invite['invite_url'])
        with self.assertRaises(PermissionError):
            repo.accept_invite(invite['invite_token'], 'wrong', accepted_email='wrong@example.com')
        member = repo.accept_invite(invite['invite_token'], 'new-account-id', accepted_email='teacher@example.com')
        self.assertEqual((member['user_id'], member['role'], member['status']), ('new-account-id', 'teacher', 'active'))
        self.assertFalse(member['seat_consumed'])
        self.assertEqual(len(records), 2)
        with self.assertRaises(ValueError):
            repo.accept_invite(invite['invite_token'], 'new-account-id', accepted_email='teacher@example.com')

    def test_repeat_for_same_school_reuses_token_and_does_not_demote_active_teacher(self):
        repo, records = self.repository()
        body = {'organization_id': 'school', 'seat_limit': 1, 'teacher_email': 'teacher@example.com'}
        first = repo.provision_education_organization(body)['teacher_membership']
        second = repo.provision_education_organization(body)['teacher_membership']
        self.assertEqual(first['invite_token'], second['invite_token'])
        repo.accept_invite(first['invite_token'], 'teacher', accepted_email='teacher@example.com')
        third = repo.provision_education_organization(body)['teacher_membership']
        self.assertEqual(third['status'], 'active')
        self.assertEqual(len(records), 1)

    def test_invalid_email_fails_before_creating_school(self):
        repo, _ = self.repository()
        for email in ('', 'bad', 'a@b', 'a b@example.com'):
            with self.subTest(email=email), self.assertRaises(ValueError):
                repo.provision_education_organization({'teacher_email': email, 'seat_limit': 60})
        repo.save_organization.assert_not_called()

    def test_invitation_mode_ignores_untrusted_typed_user_id(self):
        repo, _ = self.repository()
        member = repo.provision_education_organization({'invite_teacher': True, 'teacher_user_id': 'invented',
                                                       'teacher_email': 'teacher@example.com', 'seat_limit': 60})['teacher_membership']
        self.assertNotEqual(member['user_id'], 'invented')
        self.assertEqual(member['status'], 'pending')

    def test_teacher_email_explains_signup_and_teacher_access_in_both_languages(self):
        for locale in ('en', 'ko'):
            sender = mock.Mock()
            sent, error = send_education_invite_email(membership={'role': 'teacher', 'email': 'teacher@example.com',
                'invite_url': 'https://www.mixroom.ai/?auth=signup&invite=token'}, organization={'name': 'School'}, locale=locale, send_email=sender)
            self.assertTrue(sent)
            self.assertEqual(error, '')
            body = sender.call_args.kwargs
            self.assertIn('teacher@example.com', body['text_body'])
            self.assertIn('teacher' if locale == 'en' else '교사', body['subject'])

    def test_email_includes_app_link_and_copyable_code_for_each_role_and_language(self):
        for role in ('teacher', 'student'):
            for locale in ('en', 'ko'):
                sender = mock.Mock()
                sent, _ = send_education_invite_email(
                    membership={'role': role, 'email': 'recipient@example.com', 'invite_token': 'abc123',
                                'invite_url': 'https://www.mixroom.ai/?auth=signup&invite=abc123'},
                    organization={'name': '<Class>'}, locale=locale, send_email=sender)
                self.assertTrue(sent)
                message = sender.call_args.kwargs
                self.assertIn('\nabc123\n', message['text_body'])
                self.assertIn('mixroom://education/invites/abc123', message['text_body'])
                html = message['html_body']
                self.assertIn('>abc123</code>', html)
                self.assertLess(html.index('mixroom://'), html.index('https://'))
                self.assertIn('&lt;Class&gt;', html)
                self.assertIn('recipient@example.com', html)

    def test_resend_reuses_link_and_rejects_student_and_other_school_tokens(self):
        repo, _ = self.repository()
        invite = repo.provision_education_organization({'teacher_email': 'teacher@example.com', 'seat_limit': 60})['teacher_membership']
        with mock.patch('common.education_invites.send_education_invite_email', return_value=(False, 'delivery_failed')) as sender:
            result = resend_teacher_invite(repo, {'organization_id': 'school', 'invite_token': invite['invite_token']})
            self.assertFalse(result['email_sent'])
            self.assertEqual(result['teacher_membership']['invite_url'], invite['invite_url'])
            for changes in ({'role': 'student'}, {'organization_id': 'other'}, {'status': 'active'}):
                repo.get_membership_by_invite_token = lambda token: {**invite, **changes}
                with self.assertRaises(ValueError):
                    resend_teacher_invite(repo, {'organization_id': 'school', 'invite_token': invite['invite_token']})
            self.assertEqual(sender.call_count, 1)
