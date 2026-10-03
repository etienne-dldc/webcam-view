#!/bin/bash
# Renders WebcamView.icon (Icon Composer format) into Resources/WebcamView.png
# using Apple's own ictool (bundled with Icon Composer.app), so the result is
# the exact Liquid Glass design shown in Icon Composer — no manual drawing.
#
# Run this whenever you change the design in Icon Composer, then commit the
# resulting Resources/WebcamView.png. build.sh turns that PNG into the .icns.
#
# Requires: /Applications/Icon Composer.app (free, no Xcode needed)
#   https://developer.apple.com/icon-composer/
set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
if [ ! -x "$ICTOOL" ]; then
    echo "❌ Icon Composer not found at /Applications/Icon Composer.app" >&2
    echo "   Download it from https://developer.apple.com/icon-composer/" >&2
    exit 1
fi
if [ ! -f "WebcamView.icon/icon.json" ]; then
    echo "❌ WebcamView.icon not found" >&2
    exit 1
fi

echo "🎨 Rendering WebcamView.icon → Resources/WebcamView.png (Apple ictool)..."
"$ICTOOL" "WebcamView.icon" \
    --export-image --output-file "Resources/WebcamView.png" \
    --platform macOS --rendition Default \
    --width 1024 --height 1024 --scale 1
echo "✅ Rendered Resources/WebcamView.png"
