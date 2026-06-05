#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"
export MIXROOM_XCDEVICE_TIMEOUT=2

if [[ $# -lt 2 ]]; then
  echo "Usage: tool/run_integration_suite.sh <ios|android> <device-id>"
  echo "Example: tool/run_integration_suite.sh android emulator-5554"
  echo "Example: tool/run_integration_suite.sh ios \"iPhone 16\""
  exit 1
fi

PLATFORM="$1"
DEVICE_ID="$2"

case "$PLATFORM" in
  ios|android)
    ;;
  *)
    echo "Unsupported platform: $PLATFORM"
    echo "Use either 'ios' or 'android'."
    exit 1
    ;;
esac

flutter drive \
  --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/projects_flow_test.dart \
  --device-id="$DEVICE_ID" \
  --device-timeout=120 \
  --device-connection=attached \
  --no-dds
