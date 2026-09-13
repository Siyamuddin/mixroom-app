import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from improvement_assessment import assess

class ImprovementAssessmentTests(unittest.TestCase):
    def test_many_edits_in_one_song_do_not_prove_improvement(self):
        result = assess({'all/apply_accuracy': {'one': [1] * 1000}}, split='test')
        self.assertEqual(result['status'], 'insufficient_independent_songs')

    def test_equal_models_do_not_pass(self):
        self.assertEqual(assess({k: {str(i): [0] for i in range(12)} for k in ('all/apply_accuracy', 'all/effective_scale_mae')}, split='test')['status'], 'not_demonstrated')

    def test_consistent_improvement_needs_no_action_regression(self):
        groups = {str(i): [.2] for i in range(12)}
        data = {'all/apply_accuracy': groups, 'all/effective_scale_mae': groups}
        self.assertEqual(assess(data, split='test')['status'], 'passed')
        self.assertNotEqual(assess(data, split='validation')['status'], 'passed')
        data['ensure_effect/apply_accuracy'] = {'one': [-.1]}
        self.assertEqual(assess(data, split='test')['status'], 'not_demonstrated')
