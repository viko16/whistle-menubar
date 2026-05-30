#!/usr/bin/env bash
set -euo pipefail

APP_NAME="whistle-menubar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
MODE="${1:-}"
CONFIGURATION="${CONFIGURATION:-debug}"

if [[ "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  echo "usage: $0 [--verify|--logs|--telemetry|--debug|--release]" >&2
  exit 0
fi

stop_existing() {
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

launch_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  /bin/sleep 1
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null
}

stream_logs() {
  /usr/bin/log stream --style compact --info --predicate "process == '$APP_NAME'"
}

case "$MODE" in
  --release)
    CONFIGURATION="release"
    MODE=""
    ;;
esac

cd "$ROOT_DIR"
stop_existing
"$ROOT_DIR/script/package_app.sh" --configuration "$CONFIGURATION"

case "$MODE" in
  --verify)
    launch_app
    verify_app
    ;;
  --logs|--telemetry)
    launch_app
    stream_logs
    ;;
  --debug)
    /usr/bin/lldb "$APP_BINARY"
    ;;
  "")
    launch_app
    ;;
  *)
    echo "unknown option: $MODE" >&2
    exit 64
    ;;
esac
