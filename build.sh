#!/bin/bash
# Builds WebcamView.app from the command line (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

echo "🔨 Building WebcamView (release)..."
swift build -c release --product WebcamView

APP="build/WebcamView.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/WebcamView" "$APP/Contents/MacOS/WebcamView"

# App icon — rendered from WebcamView.icon with Apple's ictool. If the design
# changed (and Icon Composer is installed, as locally), re-render so the build
# matches; otherwise reuse the committed Resources/WebcamView.png (so builds on
# machines without Icon Composer, like CI, still get an icon).
if [ -f "WebcamView.icon/icon.json" ] && \
   [ -x "/Applications/Icon Composer.app/Contents/Executables/ictool" ]; then
    if [ ! -f "Resources/WebcamView.png" ] || \
       [ "WebcamView.icon/icon.json" -nt "Resources/WebcamView.png" ]; then
        ./Scripts/render-icon.sh
    fi
fi

if [ -f "Resources/WebcamView.png" ]; then
    echo "🎨 Generating app icon..."
    ./Scripts/make_icns.sh "Resources/WebcamView.png" "$APP/Contents/Resources/WebcamView.icns"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so macOS tracks camera permission between launches.
codesign --force --sign - "$APP" 2>/dev/null

echo "✅ Built: $APP"
