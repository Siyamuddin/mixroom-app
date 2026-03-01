import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src.common.models import default_capabilities_for_tier, free_entitlement


class ModelTests(unittest.TestCase):
    def test_free_capabilities_default(self):
        caps = default_capabilities_for_tier("free", allow_studio_tier=False)
        self.assertFalse(caps["pro_editor"])
        self.assertTrue(caps["video_projects"])

    def test_pro_capabilities(self):
        caps = default_capabilities_for_tier("pro", allow_studio_tier=False)
        self.assertTrue(caps["pro_editor"])
        self.assertTrue(caps["premium_effects"])

    def test_free_entitlement_shape(self):
        snapshot = free_entitlement("u-1", allow_studio_tier=False).to_dict()
        self.assertEqual(snapshot["user_id"], "u-1")
        self.assertEqual(snapshot["tier"], "free")


if __name__ == "__main__":
    unittest.main()
