#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?usage: smoke_test.sh <app-bundle> [app arguments ...]}"
shift
APP_NAME="Crucible"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Smoke test failed: bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cleanup() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if (($#)); then
  /usr/bin/open -n "$APP_BUNDLE" --args "$@"
else
  /usr/bin/open -n "$APP_BUNDLE"
fi

for _ in {1..50}; do
  if pgrep -x "$APP_NAME" >/dev/null; then
    break
  fi
  sleep 0.1
done

PID="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
if [[ -z "$PID" ]]; then
  echo "Smoke test failed: $APP_NAME did not launch" >&2
  exit 1
fi
echo "Smoke launch verified: $APP_NAME pid=$PID"

kill -TERM "$PID"
for _ in {1..50}; do
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "Smoke teardown verified: $APP_NAME pid=$PID exited"
    trap - EXIT
    exit 0
  fi
  sleep 0.1
done

echo "Smoke test failed: $APP_NAME did not terminate cleanly" >&2
exit 1
