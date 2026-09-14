import json
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from common.midi_boundary import extended_length


class MidiBoundaryTests(unittest.TestCase):
    def test_shared_vectors(self):
        vectors = json.loads((Path(__file__).parent / "fixtures/midi_boundary_v1.json").read_text())
        for v in vectors:
            with self.subTest(v=v):
                result = extended_length(v['original'], v['current'], v['end'], v['bpm'])
                self.assertEqual(result > v['current'], v['extended'])
                self.assertEqual(math.floor(result * (60000000.0 / v['bpm']) + .5), v['expected_us'])

    def test_invalid_numbers_do_not_extend(self):
        for invalid in (0, -1, float('nan'), float('inf')):
            self.assertEqual(extended_length(1, 1, 1.0005, invalid), 1)
