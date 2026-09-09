from __future__ import annotations

import json
import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from test_producer_capture_converter import _bundle
from verify_producer_capture import audit_document, verify_remote


def _closed():
    b = _bundle()
    b['ended_at'] = '2026-09-07T00:00:00Z'
    return b


class CaptureAuditTests(unittest.TestCase):
    def test_audit_requires_closed_session_with_actual_episodes(self):
        with self.assertRaisesRegex(ValueError, 'close'):
            audit_document(_bundle())
        b = _closed(); b['episodes'] = []
        with self.assertRaisesRegex(ValueError, 'no episodes'):
            audit_document(b)

    def test_audit_confirms_eligible_features_against_actual_resolver(self):
        report = audit_document(_closed())
        self.assertEqual(report['eligible_apply'], 1)
        self.assertEqual(report['eligible_magnitude'], 1)
        self.assertEqual(report['online_feature_parity'], 'passed')

    def test_remote_verification_compares_frozen_bytes_and_conversion(self):
        b = _closed()
        raw = json.dumps(b).encode()
        digest = hashlib.sha256(raw).hexdigest()
        cf, s3, table, session = Mock(), Mock(), Mock(), Mock()
        cf.describe_stack_resource.return_value = {'StackResourceDetail': {'PhysicalResourceId': 'test'}}
        session.client.side_effect = lambda service: cf if service == 'cloudformation' else s3
        session.resource.return_value.Table.return_value = table
        key = f'structured/user=test/session={b["session_id"]}/bundle.json'
        s3.get_paginator.return_value.paginate.return_value = [{'Contents': [{'Key': key}]}]
        table.get_item.return_value = {'Item': {'status': 'verified', 'ingestion_status': 'ready_for_conversion', 'sha256': digest, 'size_bytes': len(raw)}}
        s3.get_object.return_value = {'Body': Mock(read=lambda: raw), 'Metadata': {'sha256': digest}}
        with tempfile.TemporaryDirectory() as tmp, patch.dict('sys.modules', {'boto3': Mock(Session=lambda **kw: session)}):
            file = Path(tmp) / 'session.json'
            file.write_text(json.dumps({**b, 'upload': {'status': 'uploaded'}}))
            payload = Path(str(file) + '.payload')
            payload.write_bytes(raw)
            result = verify_remote([file], stack='test', region='test')
            self.assertEqual(result[b['session_id']]['conversion_parity'], 'passed')
            payload.write_bytes(raw + b' ')
            with self.assertRaisesRegex(ValueError, 'uploaded bytes differ'):
                verify_remote([file], stack='test', region='test')
