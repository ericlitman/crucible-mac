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

# Regression gate for the collapsed MenuBarExtra panel: open the actual
# status-item panel and require a usable viewport (AC-10's packaged-panel
# check). Requires Accessibility permission for the invoking terminal;
# set CRUCIBLE_SMOKE_SKIP_PANEL=1 only where that permission cannot exist.
if [[ "${CRUCIBLE_SMOKE_SKIP_PANEL:-0}" != "1" ]]; then
  SCREEN_LOCKED="$(python3 -c 'import Quartz; d = Quartz.CGSessionCopyCurrentDictionary() or {}; print(1 if d.get("CGSSessionScreenIsLocked", False) else 0)' 2>/dev/null || echo 0)"
  if [[ "$SCREEN_LOCKED" == "1" ]]; then
    echo "Smoke test failed: screen is locked, so the status-item panel cannot be exercised; unlock the session and rerun" >&2
    exit 1
  fi
  sleep 4
  PANEL_GEOMETRY="$(osascript <<'EOF' 2>&1 || true
tell application "System Events"
  tell process "Crucible"
    click menu bar item 1 of menu bar 2
    repeat with attempt from 1 to 10
      delay 1
      repeat with w in windows
        if subrole of w is "AXSystemDialog" then
          set windowSize to (get size of w)
          set h to item 2 of windowSize
          set sh to -1
          set g to UI element 1 of w
          repeat with c in UI elements of g
            if role of c is "AXScrollArea" then
              set scrollSize to (get size of c)
              set sh to item 2 of scrollSize
            end if
          end repeat
          key code 53
          return "panel_height=" & h & " scroll_height=" & sh
        end if
      end repeat
    end repeat
    return "panel_not_found"
  end tell
end tell
EOF
)"
  echo "Smoke panel geometry: $PANEL_GEOMETRY"
  PANEL_HEIGHT="$(sed -n 's/.*panel_height=\([0-9]*\).*/\1/p' <<<"$PANEL_GEOMETRY")"
  SCROLL_HEIGHT="$(sed -n 's/.*scroll_height=\([0-9]*\).*/\1/p' <<<"$PANEL_GEOMETRY")"
  if [[ -z "$PANEL_HEIGHT" || -z "$SCROLL_HEIGHT" ]]; then
    echo "Smoke test failed: status-item panel not found or Accessibility permission missing ($PANEL_GEOMETRY)" >&2
    exit 1
  fi
  if ((PANEL_HEIGHT < 200 || SCROLL_HEIGHT < 100)); then
    echo "Smoke test failed: status-item panel viewport collapsed (panel=$PANEL_HEIGHT scroll=$SCROLL_HEIGHT)" >&2
    exit 1
  fi
  echo "Smoke panel viewport verified: panel=$PANEL_HEIGHT scroll=$SCROLL_HEIGHT"
fi

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
