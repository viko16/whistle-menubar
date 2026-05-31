#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/Sources/WhistleMenuBarApp/Resources"
APP_SVG="$RESOURCE_DIR/AppIcon.svg"
STATUS_SVG="$RESOURCE_DIR/StatusBarIconTemplate.svg"
ICONSET_DIR="$ROOT_DIR/.build/generated-icons/AppIcon.iconset"
RSVG_CONVERT="${RSVG_CONVERT:-rsvg-convert}"

render_svg() {
  local source="$1"
  local size="$2"
  local output="$3"

  "$RSVG_CONVERT" -w "$size" -h "$size" -o "$output" "$source"
}

/usr/bin/command -v "$RSVG_CONVERT" >/dev/null

/bin/rm -rf "$ICONSET_DIR"
/bin/mkdir -p "$ICONSET_DIR"

render_svg "$APP_SVG" 16 "$ICONSET_DIR/icon_16x16.png"
render_svg "$APP_SVG" 32 "$ICONSET_DIR/icon_16x16@2x.png"
render_svg "$APP_SVG" 32 "$ICONSET_DIR/icon_32x32.png"
render_svg "$APP_SVG" 64 "$ICONSET_DIR/icon_32x32@2x.png"
render_svg "$APP_SVG" 128 "$ICONSET_DIR/icon_128x128.png"
render_svg "$APP_SVG" 256 "$ICONSET_DIR/icon_128x128@2x.png"
render_svg "$APP_SVG" 256 "$ICONSET_DIR/icon_256x256.png"
render_svg "$APP_SVG" 512 "$ICONSET_DIR/icon_256x256@2x.png"
render_svg "$APP_SVG" 512 "$ICONSET_DIR/icon_512x512.png"
render_svg "$APP_SVG" 1024 "$ICONSET_DIR/icon_512x512@2x.png"
render_svg "$STATUS_SVG" 72 "$RESOURCE_DIR/StatusBarIconTemplate.png"

/usr/bin/python3 - "$ICONSET_DIR" "$RESOURCE_DIR/AppIcon.icns" <<'PY'
import struct
import sys
from pathlib import Path

iconset = Path(sys.argv[1])
output = Path(sys.argv[2])
entries = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_16x16@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic04", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_128x128@2x.png"),
    ("ic09", "icon_256x256@2x.png"),
    ("ic13", "icon_256x256@2x.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic14", "icon_512x512@2x.png"),
]

body = bytearray()
for fourcc, filename in entries:
    png = (iconset / filename).read_bytes()
    body += fourcc.encode("ascii")
    body += struct.pack(">I", len(png) + 8)
    body += png

output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY

echo "Generated $RESOURCE_DIR/AppIcon.icns"
echo "Generated $RESOURCE_DIR/StatusBarIconTemplate.png"
