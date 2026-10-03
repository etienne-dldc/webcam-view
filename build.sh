#!/bin/bash
# Builds WebcamView.app from the command line (no Xcode needed for the base
# build; Xcode is only used for the adaptive app icon, when present).
set -euo pipefail
cd "$(dirname "$0")"

echo "🔨 Building WebcamView (release)..."
swift build -c release --product WebcamView

APP="build/WebcamView.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/WebcamView" "$APP/Contents/MacOS/WebcamView"

cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon. Two paths:
#   1) Preferred — Xcode installed: compile WebcamView.icon into an adaptive
#      Assets.car (Default/Dark/Mono appearances) + a legacy .icns (actool).
#   2) Fallback — no Xcode (e.g. CI): reuse the committed render
#      Resources/WebcamView.png → .icns via sips/iconutil. macOS 26 derives the
#      other appearances automatically from the single light icon.
if xcrun -q --find actool >/dev/null 2>&1; then
    ./Scripts/compile-icon.sh "$APP"
else
    # Keep the ictool renders fresh when Icon Composer is installed locally.
    ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
    RENDER_FILES="Resources/WebcamView.png Resources/WebcamView-Dark.png Resources/WebcamView-Mono.png"
    if [ -f "WebcamView.icon/icon.json" ] && [ -x "$ICTOOL" ]; then
        needs_render=false
        for f in $RENDER_FILES; do
            [ -f "$f" ] || needs_render=true
        done
        if [ "$needs_render" = false ] && \
           find WebcamView.icon -type f \( -name '*.json' -o -name '*.svg' \) \
                -newer Resources/WebcamView.png | grep -q .; then
            needs_render=true
        fi
        if [ "$needs_render" = true ]; then
            ./Scripts/render-icon.sh
        fi
    fi
    if [ -f "Resources/WebcamView.png" ]; then
        echo "🎨 Generating app icon (.icns)..."
        ./Scripts/make_icns.sh "Resources/WebcamView.png" "$APP/Contents/Resources/WebcamView.icns"
    fi
fi

# Ad-hoc sign so macOS tracks camera permission between launches.
codesign --force --sign - "$APP" 2>/dev/null

echo "✅ Built: $APP"
