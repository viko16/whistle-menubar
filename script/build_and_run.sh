#!/usr/bin/env bash
set -euo pipefail

APP_NAME="whistle-menubar"
PRODUCT_NAME="whistle-menubar"
BUNDLE_ID="com.viko16.whistle-menubar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

MODE="${1:-}"

stop_existing() {
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  swift build --product "$PRODUCT_NAME"
}

stage_bundle() {
  local binary_path
  binary_path="$(swift build --show-bin-path)/$PRODUCT_NAME"

  /bin/rm -rf "$APP_BUNDLE"
  /bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
  /bin/cp "$binary_path" "$MACOS_DIR/$APP_NAME"
  /bin/chmod +x "$MACOS_DIR/$APP_NAME"

  /bin/cp -R "$ROOT_DIR/Sources/WhistleMenuBarCore/Resources/zh-Hans.lproj" "$RESOURCES_DIR/"
  /bin/cp -R "$ROOT_DIR/Sources/WhistleMenuBarCore/Resources/en.lproj" "$RESOURCES_DIR/"

  /usr/bin/find "$ROOT_DIR/.build" \
    \( -name 'WhistleMenuBarCore_WhistleMenuBarCore.resources' -o -name 'WhistleMenuBarCore_WhistleMenuBarCore.bundle' \) \
    -maxdepth 6 -type d -exec /bin/cp -R {} "$RESOURCES_DIR/" \; >/dev/null 2>&1 || true

  /bin/cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
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

cd "$ROOT_DIR"
stop_existing
build_app
stage_bundle

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
    /usr/bin/lldb "$MACOS_DIR/$APP_NAME"
    ;;
  "")
    launch_app
    ;;
  *)
    echo "unknown option: $MODE" >&2
    exit 64
    ;;
esac
