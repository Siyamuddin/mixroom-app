#!/usr/bin/env python3
"""Exercise the real relay with a named protocol fixture, never a native edit.

--speech makes two small ElevenLabs calls. --restart restarts this Compose
service only, so use it before connecting a musician's active session.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import time
import uuid

from dotenv import dotenv_values
import httpx

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--speech', action='store_true')
parser.add_argument('--restart', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
config = dotenv_values(root / '.env')
report = {}
with httpx.Client(base_url='http://127.0.0.1:8765', timeout=90) as client:
    assert client.get('/health').json()['ok']
    login = client.post('/api/auth/login', json={'password': config['MIXROOM_PASSWORD']})
    login.raise_for_status()
    owner = {'Authorization': 'Bearer ' + login.json()['access_token']}
    pair = client.post('/api/voice/pairing', headers=owner, json={})
    pair.raise_for_status()
    pair = pair.json()
    sid = pair['sessionId']
    route = '/api/voice/sessions/' + sid
    try:
        claimed = client.post('/api/voice/pairing/claim', json={'pairingCode': pair['pairingCode'], 'deviceName': 'Protocol smoke fixture'})
        claimed.raise_for_status()
        native = {'Authorization': 'Bearer ' + claimed.json()['deviceToken']}
        assert client.post('/api/voice/pairing/claim', json={'pairingCode': pair['pairingCode']}).status_code == 410
        client.put(route + '/state', headers=native, json={'projectSessionId': 'protocol-fixture', 'projectRevision': 1, 'state': {'projectName': 'Protocol fixture — no native edit', 'projectReady': True}}).raise_for_status()
        command = {'version': 1, 'commandId': str(uuid.uuid4()), 'sessionId': sid, 'projectSessionId': 'protocol-fixture', 'expectedProjectRevision': 1,
                   'kind': 'session_action', 'args': {'type': 'notes.list', 'arguments': {}}, 'expiresAt': (datetime.now(timezone.utc) + timedelta(seconds=90)).isoformat()}
        client.post(route + '/commands', headers=owner, json=command).raise_for_status()
        retry = client.post(route + '/commands', headers=owner, json=command)
        retry.raise_for_status()
        assert retry.json()['duplicate']
        assert client.get(route + '/poll', headers=native).json()['command']['commandId'] == command['commandId']
        assert client.get(route + '/poll', headers=native).json()['command'] is None
        client.post(route + '/results', headers=native, json={'commandId': command['commandId'], 'status': 'succeeded', 'message': 'Protocol fixture only; no native edit.'}).raise_for_status()
        assert client.get(route + '/commands/' + command['commandId'], headers=owner).json()['status'] == 'succeeded'
        report.update(health='passed', authentication='passed', pairing='passed', command_deduplication='passed', single_claim='passed', result_receipt='passed')
        if args.restart:
            subprocess.run(['docker', 'compose', 'restart', 'backend'], cwd=root, check=True, capture_output=True)
            for attempt in range(30):
                try:
                    response = client.get('/health')
                    if response.status_code == 200: break
                except httpx.TransportError: pass
                time.sleep(0.5)
            persisted = client.get(route + '/commands/' + command['commandId'], headers=owner)
            persisted.raise_for_status()
            assert persisted.json()['status'] == 'succeeded'
            report['container_restart_persistence'] = 'passed'
        if args.speech:
            token = client.post('/api/voice/speech/token', headers=owner, json={'sessionId': sid})
            token.raise_for_status()
            assert token.json().get('token')
            audio = client.post('/api/voice/speech/tts', headers=owner, json={'sessionId': sid, 'text': 'MixRoom is running locally in Docker.'})
            audio.raise_for_status()
            assert len(audio.content) > 1000
            report.update(elevenlabs_token_proxy='passed', elevenlabs_audio_proxy='passed', audio_bytes=len(audio.content))
        report['native_edit_performed'] = False
        print(json.dumps(report))
    finally:
        client.delete(route, headers=owner)
        client.post('/api/auth/logout', headers=owner)
