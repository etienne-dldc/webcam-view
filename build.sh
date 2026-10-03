#!/bin/bash
# Builds WebcamView.app from the command line.
#
# The app icon is compiled from WebcamView.icon with Xcode's actool into an
# adaptive Assets.car (Default/Dark/Mono appearances) + a legacy .icns, so
# full Xcode is required. That's fine — the icon rarely changes.
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

# App icon — always compiled from WebcamView.icon via actool (Xcode required).
./Scripts/compile-icon.sh "$APP"

# Ad-hoc sign so macOS tracks camera permission between launches.
codesign --force --sign - "$APP" 2>/dev/null

echo "✅ Built: $APP"
