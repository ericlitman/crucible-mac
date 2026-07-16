#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Crucible"
BUNDLE_ID="com.mobilyze.Crucible"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Crucible/Crucible.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build

APP_ARGUMENTS=()
if [[ "${CRUCIBLE_PREVIEW_DATA:-0}" == "1" ]]; then
  APP_ARGUMENTS+=(--preview-data)
fi

open_app() {
  if ((${#APP_ARGUMENTS[@]})); then
    /usr/bin/open -n "$APP_BUNDLE" --args "${APP_ARGUMENTS[@]}"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY" "${APP_ARGUMENTS[@]}"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    "$ROOT_DIR/script/smoke_test.sh" "$APP_BUNDLE" "${APP_ARGUMENTS[@]}"
    ;;
esac
