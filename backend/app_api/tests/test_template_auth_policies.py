from __future__ import annotations

import unittest
from pathlib import Path


class TemplateAuthPolicyTests(unittest.TestCase):
    def test_social_auth_function_can_write_entitlements(self) -> None:
        template = Path(__file__).resolve().parents[1] / "template.yaml"
        text = template.read_text(encoding="utf-8")

        social_section = text.split("  SocialAuthApiFunction:", maxsplit=1)[1]
        social_section = social_section.split("  AdminOverviewApiFunction:", maxsplit=1)[0]

        self.assertIn("        - DynamoDBCrudPolicy:\n            TableName: !Ref EntitlementsCurrentTable", social_section)


if __name__ == "__main__":
    unittest.main()
