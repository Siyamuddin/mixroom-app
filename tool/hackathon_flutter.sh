#!/usr/bin/env bash
set -euo pipefail

task_command="${1:-}"
shift || true
if [[ "$task_command" != "run" && "$task_command" != "build" ]]; then
  echo 'Use tool/run_hackathon.sh or tool/build_hackathon.sh.' >&2
  exit 2
fi
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_relay_url="${MIXROOM_VOICE_RELAY_URL:-http://127.0.0.1:8765/api/voice}"
task_mode=debug
[[ "$task_command" == build ]] && task_mode=release
task_dry_run=false
task_no_pub=false

usage() {
  cat <<'EOF'
Usage: tool/run_hackathon.sh [--relay-url URL] [--debug|--profile|--release] [--no-pub] [--dry-run]
       tool/build_hackathon.sh [the same options]

Uses the independent Hackathon macOS flavor and the local Python/Docker relay
at http://127.0.0.1:8765/api/voice. Override its URL with --relay-url or
MIXROOM_VOICE_RELAY_URL. No API keys or private dart-define files are accepted.
Run defaults to debug; build defaults to release.
--dry-run prints the command without fetching packages, building, or launching.
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --relay-url)
      [[ $# -ge 2 && -n "$2" ]] || { echo '--relay-url needs a URL.' >&2; exit 2; }
      task_relay_url="$2"; shift 2 ;;
    --debug|--profile|--release) task_mode="${1#--}"; shift ;;
    --no-pub) task_no_pub=true; shift ;;
    --dry-run) task_dry_run=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo 'Unsupported option. Use --help for the allowed public build settings.' >&2; exit 2 ;;
  esac
done

if [[ -z "$task_relay_url" ]]; then
  echo 'Set MIXROOM_VOICE_RELAY_URL or pass --relay-url with the public voice relay URL.' >&2
  exit 2
fi
python3 - "$task_relay_url" <<'PY'
import sys
from urllib.parse import urlparse
try:
    parsed = urlparse(sys.argv[1])
    allowed_transport = parsed.scheme == 'https' or (parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1', '::1'))
    valid = allowed_transport and bool(parsed.hostname) and not parsed.username and not parsed.password and not parsed.query and not parsed.fragment
    _ = parsed.port
except ValueError:
    valid = False
if not valid:
    raise SystemExit('Use a public HTTPS relay URL (or local HTTP loopback), without credentials, query, or fragment.')
PY

cd "$task_repo_root"
[[ -f macos/Runner.xcodeproj/xcshareddata/xcschemes/Hackathon.xcscheme ]] || {
  echo 'Hackathon scheme is missing. Run ruby tool/configure_hackathon_macos.rb first.' >&2
  exit 2
}
task_flutter_args=(flutter "$task_command")
if [[ "$task_command" == run ]]; then
  task_flutter_args+=(-d macos)
else
  task_flutter_args+=(macos)
fi
task_flutter_args+=(--flavor Hackathon "--$task_mode" --dart-define=MIXROOM_HACKATHON=true "--dart-define=MIXROOM_VOICE_RELAY_URL=$task_relay_url")
[[ "$task_no_pub" == true ]] && task_flutter_args+=(--no-pub)
if [[ "$task_dry_run" == true ]]; then
  printf '%q ' "${task_flutter_args[@]}"
  printf '\n'
  exit 0
fi
exec "${task_flutter_args[@]}"
