import unittest
from copy import deepcopy
from unittest import mock
import support  # noqa: F401
from src.common.collaboration_repository import CollaborationRepository


class EducationClassLinksTests(unittest.TestCase):
    def setUp(self):
        self.repo = CollaborationRepository.__new__(CollaborationRepository)
        self.org = {'entity_id': 'organization#class', 'organization_id': 'class', 'plan_code': 'education', 'status': 'active', 'seat_limit': 2}
        self.records = {self.org['entity_id']: self.org}
        self.repo._table = mock.Mock()
        self.repo._table.name = 'test-table'
        self.repo._get_item = lambda key: deepcopy(self.records.get(key, {}))
        self.repo.get_organization = lambda key: deepcopy(self.records.get('organization#' + key, {}))
        self.repo.list_memberships = lambda **kw: [deepcopy(m) for m in self.records.values() if m.get('entity_type') == 'membership']
        self.repo._consistent_memberships = lambda org: self.repo.list_memberships()
        self.repo._table.put_item.side_effect = lambda Item, **kw: self.records.update({Item['entity_id']: deepcopy(Item)})
        self.repo._table.update_item.side_effect = lambda Key, **kw: self.records[Key['entity_id']].update(status='revoked')
        self.repo._table.delete_item.side_effect = lambda Key: self.records.pop(Key['entity_id'], None)
        def commit(TransactItems):
            for item in TransactItems:
                if 'Put' in item:
                    record = item['Put']['Item']
                    self.records[record['entity_id']] = deepcopy(record)
                if 'Delete' in item:
                    self.records.pop(item['Delete']['Key']['entity_id'], None)
                if 'Update' in item:
                    update = item['Update']
                    self.records[update['Key']['entity_id']]['seat_revision'] = update['ExpressionAttributeValues'][':next']
        self.repo._table.meta.client.transact_write_items.side_effect = commit
        self.link = self.repo.education_class_link('class', 'create')

    def join(self, user='student', token=None):
        return self.repo.accept_invite(token or self.link['invite_token'], user, accepted_email=user+'@example.com')

    def test_generation_does_not_reserve_a_seat_and_reuses_current_link(self):
        self.assertEqual(self.repo.list_memberships(), [])
        self.assertEqual(self.repo.education_class_link('class', 'create')['invite_token'], self.link['invite_token'])
        self.assertIn('invite=edu.', self.link['invite_url'])

    def test_students_join_without_individual_email_invites_and_repeat_is_idempotent(self):
        member = self.join()
        self.assertEqual((member['role'], member['status'], member['seat_consumed']), ('student', 'active', True))
        self.assertEqual(self.join()['entity_id'], member['entity_id'])
        self.assertEqual(len(self.repo.list_memberships()), 1)
        operations = self.repo._table.meta.client.transact_write_items.call_args.kwargs['TransactItems']
        self.assertTrue(any('ConditionCheck' in op for op in operations))

    def test_full_class_blocks_new_join_but_allows_same_student(self):
        self.join('one'); self.join('two')
        with self.assertRaisesRegex(ValueError, 'seat limit'):
            self.join('three')
        self.assertEqual(self.join('one')['user_id'], 'one')

    def test_existing_email_invitation_is_consumed_without_an_extra_seat(self):
        self.repo.save_membership({'organization_id': 'class', 'email': 'student@example.com', 'status': 'pending', 'role': 'student', 'seat_consumed': True})
        self.join('other')
        self.join()
        self.assertEqual(len(self.repo.list_memberships()), 2)
        self.assertTrue(all(m['status']=='active' for m in self.repo.list_memberships()))

    def test_revoke_stops_new_joins_and_regeneration_changes_token(self):
        self.join()
        self.repo.education_class_link('class', 'revoke')
        with self.assertRaisesRegex(ValueError, 'revoked'):
            self.join('other')
        new = self.repo.education_class_link('class', 'create')
        self.assertNotEqual(new['invite_token'], self.link['invite_token'])
        self.assertEqual(self.repo.get_membership('class', 'student')['status'], 'active')

    def test_class_expiry_and_removed_members_cannot_be_bypassed(self):
        member = self.join()
        self.records[member['entity_id']]['status'] = 'removed'
        with self.assertRaisesRegex(ValueError, 'removed'):
            self.join()
        self.org['access_expires_at'] = '2020-01-01T00:00:00Z'
        with self.assertRaisesRegex(ValueError, 'ended'):
            self.join('other')

    def test_teacher_invitation_cannot_be_claimed_as_student(self):
        self.repo.save_membership({'organization_id': 'class', 'email': 'teacher@example.com', 'status': 'pending', 'role': 'teacher', 'seat_consumed': False})
        with self.assertRaisesRegex(ValueError, 'teacher invitation'):
            self.join('teacher')

    def test_invalid_token_and_signed_out_join_are_rejected(self):
        with self.assertRaises(ValueError):
            self.join(token=self.link['invite_token'][:-1] + 'x')
        with self.assertRaises(PermissionError):
            self.repo.accept_invite(self.link['invite_token'], '', accepted_email='')

    def test_short_code_accepts_lowercase_and_optional_hyphen(self):
        code = self.link['invite_code']
        self.assertRegex(code, r'^[2-9A-HJ-NP-Z]{5}-[2-9A-HJ-NP-Z]{5}$')
        self.assertEqual(self.repo.education_class_link('class')['invite_code'], code)
        self.assertEqual(self.join(token=code.lower())['status'], 'active')
        self.assertEqual(self.join('other', token=code.replace('-', ''))['status'], 'active')
        operations = self.repo._table.meta.client.transact_write_items.call_args.kwargs['TransactItems']
        check = next(op['ConditionCheck'] for op in operations if 'ConditionCheck' in op)
        self.assertEqual(check['ExpressionAttributeValues'][':token'], self.link['invite_token'])

    def test_revoked_short_code_stays_invalid_after_regeneration(self):
        old = self.link['invite_code']
        self.repo.education_class_link('class', 'revoke')
        new = self.repo.education_class_link('class', 'create')
        self.assertNotEqual(old, new['invite_code'])
        with self.assertRaisesRegex(ValueError, 'revoked'):
            self.join(token=old)
        self.assertEqual(self.join(token=new['invite_code'])['status'], 'active')

    def test_existing_long_link_gets_short_code_without_rotation(self):
        for key in list(self.records):
            if key.startswith('education_code#'):
                del self.records[key]
        loaded = self.repo.education_class_link('class')
        self.assertEqual(loaded['invite_token'], self.link['invite_token'])
        self.assertEqual(self.join(token=loaded['invite_code'])['status'], 'active')

    def test_short_code_collision_retries_without_overwriting_another_class(self):
        from botocore.exceptions import ClientError
        original = self.repo._table.put_item.side_effect
        collision = ClientError({'Error': {'Code': 'ConditionalCheckFailedException'}}, 'PutItem')
        self.repo._table.put_item.side_effect = [collision, None]
        result = self.repo.education_class_link('class')
        self.assertNotEqual(result['invite_code'], self.link['invite_code'])
        self.repo._table.put_item.side_effect = original
