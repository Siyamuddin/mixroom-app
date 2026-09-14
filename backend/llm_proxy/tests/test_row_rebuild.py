import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
from common import v3_server_contract as contract
from common.v3_pitch_repair import plan_payload
sys.path.insert(0, str(ROOT.parents[1] / 'tool/ai_v3_eval'))
from row_rebuild_candidate import candidate, OLD, NEW
from row_rebuild_revision import historical_instructions


class RowRebuildTests(unittest.TestCase):
    def test_candidate_changes_only_capacity_paragraph(self):
        assets = ROOT / 'src/common/v3_contract_assets'
        for name in ('v3_instructions.txt', 'v3_instructions_resource_refs.txt'):
            original = historical_instructions((assets / name).read_text())
            changed = candidate(original)
            self.assertEqual(changed.replace(NEW, OLD), original)
            self.assertEqual(changed.splitlines()[-1], original.splitlines()[-1])
            with self.assertRaises(ValueError):
                candidate(changed)

    def test_shared_rebuild_fixtures(self):
        fixture = json.loads((Path(__file__).parent / 'fixtures/row_rebuild_v1.json').read_text())
        for case in fixture['cases']:
            with self.subTest(case=case['name']):
                surface = contract.extract_capability_surface(case['context'])
                def validate():
                    return contract.parse_and_validate_provider_plan(
                        plan_payload(case['plan']), command_types=contract.SERVER_COMMAND_TYPES,
                        resource_refs_enabled=True, capability_surface=surface,
                        original_request=fixture['original_request'])
                if case['backend_error']:
                    with self.assertRaises(contract.V3ContractError) as raised:
                        validate()
                    self.assertEqual(raised.exception.code, case['backend_error'])
                else:
                    self.assertEqual(validate(), case['plan'])


if __name__ == '__main__':
    unittest.main()
