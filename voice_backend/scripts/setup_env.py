#!/usr/bin/env python3
"""Create local configuration without printing credentials or replacing a file."""
from pathlib import Path
import os
import secrets

root = Path(__file__).resolve().parents[1]
target = root / '.env'
if target.exists():
    raise SystemExit('Existing .env preserved. Edit it locally to update provider keys.')
text = (root / '.env.example').read_text().replace(
    'replace-with-at-least-12-random-characters', secrets.token_urlsafe(32)
)
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(text)
print('Created private .env. Add provider keys there; use MIXROOM_PASSWORD to sign in.')
