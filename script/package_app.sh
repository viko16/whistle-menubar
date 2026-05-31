#!/usr/bin/env bash
set -euo pipefail

APP_NAME="whistle-menubar"
PRODUCT_NAME="whistle-menubar"
BUNDLE_ID="com.viko16.whistle-menubar"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

usage() {
  cat >&2 <<USAGE
usage: $0 [--configuration debug|release] [--unsigned]

Build and package dist/$APP_NAME.app without launching it.

Environment:
  CONFIGURATION   Swift build configuration, default: release
  SIGN_IDENTITY   codesign identity, default: - (ad-hoc)
  SKIP_CODESIGN   set to 1 to skip codesign
  VERSION         CFBundleShortVersionString, default: 0.1.0
  BUILD_NUMBER    CFBundleVersion, default: 1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      if [[ $# -lt 2 ]]; then
        echo "--configuration requires debug or release" >&2
        usage
        exit 64
      fi
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --unsigned)
      SKIP_CODESIGN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "invalid configuration: $CONFIGURATION" >&2
    usage
    exit 64
    ;;
esac

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"
BUILD_BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BINARY_PATH="$BUILD_BIN_DIR/$PRODUCT_NAME"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
/bin/cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
/bin/chmod +x "$MACOS_DIR/$APP_NAME"

/bin/cp -R "$ROOT_DIR/Sources/WhistleMenuBarApp/Resources/." "$RESOURCES_DIR/"
/bin/cp -R "$ROOT_DIR/Sources/WhistleMenuBarCore/Resources/zh-Hans.lproj" "$RESOURCES_DIR/"
/bin/cp -R "$ROOT_DIR/Sources/WhistleMenuBarCore/Resources/en.lproj" "$RESOURCES_DIR/"

SWIFTPM_RESOURCE_BUNDLE="$BUILD_BIN_DIR/${PRODUCT_NAME}_WhistleMenuBarCore.bundle"
if [[ -d "$SWIFTPM_RESOURCE_BUNDLE" ]]; then
  /bin/cp -R "$SWIFTPM_RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

while IFS= read -r resource_bundle; do
  /bin/cp -R "$resource_bundle" "$RESOURCES_DIR/"
done < <(/usr/bin/find "$ROOT_DIR/.build" -maxdepth 8 -type d \( -name 'WhistleMenuBarCore_WhistleMenuBarCore.resources' -o -name 'WhistleMenuBarCore_WhistleMenuBarCore.bundle' \) 2>/dev/null)

/bin/cat > "$INFO_PLIST" <<PLIST
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
[[ -x "$MACOS_DIR/$APP_NAME" ]]

if [[ "$SKIP_CODESIGN" != "1" ]]; then
  /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE" >/dev/null
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
fi

echo "Packaged $APP_BUNDLE"
