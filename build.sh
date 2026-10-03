#!/bin/bash
# Builds WebcamView.app from the command line (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

echo "🔨 Building WebcamView (release)..."
swift build -c release --product WebcamView

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/WebcamView.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WebcamView" "$APP/Contents/MacOS/WebcamView"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so macOS tracks camera permission per-build.
codesign --force --sign - "$APP" 2>/dev/null

echo "✅ Built: $APP"
