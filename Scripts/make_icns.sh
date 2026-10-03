#!/bin/bash
# Packages a single 1024×1024 PNG into an .icns using /usr/bin/sips + iconutil.
# No Xcode or Icon Composer needed, so this also runs fine on CI.
#
# Usage: make_icns.sh <input-1024x1024.png> <output.icns>
set -euo pipefail

SRC="${1:?usage: make_icns.sh <input-1024.png> <output.icns>}"
OUT="${2:?}"

WORK="$(mktemp -d)"
TMP="$WORK/WebcamView.iconset"
mkdir -p "$TMP"
trap 'rm -rf "$WORK"' EXIT

scale() { sips -z "$2" "$2" "$SRC" --out "$TMP/$1" >/dev/null; }
scale icon_16x16.png 16
scale icon_16x16@2x.png 32
scale icon_32x32.png 32
scale icon_32x32@2x.png 64
scale icon_128x128.png 128
scale icon_128x128@2x.png 256
scale icon_256x256.png 256
scale icon_256x256@2x.png 512
scale icon_512x512.png 512
scale icon_512x512@2x.png 1024

iconutil -c icns "$TMP" -o "$OUT"
echo "✅ Wrote $OUT"
