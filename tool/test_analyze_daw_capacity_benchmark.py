"""Offline regression tests for the synthetic action measurement reader."""
import json
import tempfile
import unittest
from pathlib import Path

from analyze_daw_capacity_benchmark import summarize


class BenchmarkAnalysisTests(unittest.TestCase):
    def events(self):
        return [dict(session_id='synthetic', operation_id=i, variant='baseline',
                     rows=40, clips=20, operation='add_row', run=0,
                     event=kind, elapsed_ms=value, result='success')
                for i, value in enumerate([1, 2, 3, 4])
                for kind in ('operation_end', 'operation_visible_frame')]

    def read(self, events):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'measurements.jsonl'
            path.write_text(''.join('[PRO17_PERF] ' + json.dumps(event) + '\n'
                                    for event in events))
            return summarize([path])

    def test_statistics_and_order_independence(self):
        result = self.read(self.events())
        self.assertEqual(result, self.read(list(reversed(self.events()))))
        metric = result['groups'][0]['metrics']['operation_end']
        self.assertEqual(metric['count'], 4)
        self.assertEqual(metric['median_ms'], 2.5)
        self.assertAlmostEqual(metric['p95_ms'], 3.85)
        self.assertEqual(metric['max_ms'], 4)

    def test_rejects_duplicate_samples(self):
        with self.assertRaises(ValueError):
            self.read(self.events() * 2)

    def test_rejects_missing_visible_frame(self):
        with self.assertRaises(ValueError):
            self.read(self.events()[:-1])

    def test_failed_action_is_not_silently_dropped(self):
        events = self.events()
        events[0]['result'] = 'failure'
        with self.assertRaises(ValueError):
            self.read(events)

    def test_invalid_measurements(self):
        for value in (True, -1, float('nan'), float('inf'), '1', None):
            with self.subTest(value=value):
                events = self.events()
                events[0]['elapsed_ms'] = value
                with self.assertRaises(ValueError):
                    self.read(events)

    def test_warmups_excluded(self):
        events = self.events()
        for event in events[:2]:
            event['warmup'] = True
        metric = self.read(events)['groups'][0]['metrics']['operation_end']
        self.assertEqual(metric['count'], 3)
        self.assertEqual(metric['median_ms'], 3)


if __name__ == '__main__':
    unittest.main()
