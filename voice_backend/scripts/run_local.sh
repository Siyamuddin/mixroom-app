#!/usr/bin/env bash
set -euo pipefail
task_backend_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_backend_root"
[[ -f .env ]] || python3 scripts/setup_env.py
[[ -x .venv/bin/python ]] || python3 -m venv .venv
.venv/bin/python -m pip install --disable-pip-version-check -r requirements.txt
command -v node >/dev/null || { echo 'Install Node 22.18+ for the bundled planner.' >&2; exit 1; }
mkdir -p data
export MIXROOM_DATA_DIR="$task_backend_root/data"
exec .venv/bin/python -m uvicorn mixroom_backend.app:app --env-file .env --host 127.0.0.1 --port 8765 --workers 1 --no-access-log --no-proxy-headers
