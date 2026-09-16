from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

TRAINING_ROOT = Path(__file__).resolve().parents[1]
if str(TRAINING_ROOT) not in sys.path:
    sys.path.insert(0, str(TRAINING_ROOT))

from producer_training_status import summarize  # noqa: E402


class ProducerTrainingStatusTests(unittest.TestCase):
    def test_reports_stale_uploads_and_ignores_deleted_sessions(self) -> None:
        now = datetime(2026, 8, 26, tzinfo=timezone.utc)
        old = (now - timedelta(hours=25)).isoformat()
        stored = (now - timedelta(hours=24)).isoformat()
        report = summarize(
            [
                {
                    "status": "verified",
                    "ingestion_status": "ready_for_conversion",
                    "reserved_at": old,
                    "stored_at": stored,
                },
                {
                    "status": "reserved",
                    "ingestion_status": "awaiting_upload",
                    "reserved_at": old,
                },
                {
                    "status": "deleted",
                    "ingestion_status": "deleted",
                    "reserved_at": old,
                },
            ],
            now=now,
        )
        self.assertEqual(report["session_count"], 2)
        self.assertEqual(report["deleted_session_count"], 1)
        self.assertEqual(report["stale_over_24h_count"], 1)
        self.assertEqual(report["verified_ingestion_rate"], 0.5)
        self.assertFalse(report["meets_95_percent_sla"])


if __name__ == "__main__":
    unittest.main()
