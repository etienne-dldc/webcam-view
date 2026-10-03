#!/bin/bash
# Compiles WebcamView.icon into the adaptive app icon using Xcode's actool.
# Produces, in <app>/Contents/Resources/:
#   Assets.car            — asset catalog carrying the Default/Dark/Mono (+
#                           tinted/clear) appearances, read by macOS 26
#   WebcamView.icns       — legacy single-appearance icon for older macOS
# and sets CFBundleIconFile/CFBundleIconName in the app's Info.plist.
#
# Requires: full Xcode (actool is not part of the Command Line Tools).
#   xcode-select --install only installs CLT; you need the real Xcode.app.
#   Install it (App Store id 497799835), then this script finds actool.
#
# Usage: compile-icon.sh <path-to-.app>
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: compile-icon.sh <path-to-.app>}"

# actool lives inside Xcode.app. Prefer the active developer dir (xcrun), but
# also try the well-known path so we don't require `sudo xcode-select -s` if
# Xcode is installed but not the active developer directory.
ACTOOL="$(xcrun --find actool 2>/dev/null)" || true
if [ -z "$ACTOOL" ] && [ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/actool" ]; then
    ACTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/actool"
fi
if [ -z "$ACTOOL" ]; then
    echo "❌ actool not found. Install Xcode from the Mac App Store (id 497799835)" >&2
    echo "   then: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch" >&2
    exit 1
fi

if [ ! -d "$APP" ] || [ ! -d "$APP/Contents/Resources" ]; then
    echo "❌ Not an app bundle: $APP" >&2
    exit 1
fi
if [ ! -f "WebcamView.icon/icon.json" ]; then
    echo "❌ WebcamView.icon not found" >&2
    exit 1
fi

RES="$APP/Contents/Resources"
INFO="$APP/Contents/Info.plist"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "🎨 Compiling WebcamView.icon → Assets.car + WebcamView.icns (actool) ..."
"$ACTOOL" "WebcamView.icon" \
    --compile "$TMP" \
    --app-icon WebcamView \
    --platform macosx \
    --target-device mac \
    --output-format human-readable-text \
    --minimum-deployment-target "$(plutil -extract LSMinimumSystemVersion raw -o - "$INFO")" \
    --output-partial-info-plist "$TMP/partial.plist"

if [ -f "$TMP/Assets.car" ]; then
    cp "$TMP/Assets.car" "$RES/Assets.car"
    echo "  → $RES/Assets.car"
else
    echo "⚠️  actool produced no Assets.car" >&2
fi
if [ -f "$TMP/WebcamView.icns" ]; then
    cp "$TMP/WebcamView.icns" "$RES/WebcamView.icns"
    echo "  → $RES/WebcamView.icns"
else
    echo "⚠️  actool produced no WebcamView.icns" >&2
fi

# Point the system at the adaptive icon (Assets.car) and the legacy .icns.
plutil -replace CFBundleIconFile -string WebcamView "$INFO"
plutil -replace CFBundleIconName -string WebcamView "$INFO" || \
    plutil -insert CFBundleIconName -string WebcamView "$INFO"

# Invalidate the icon cache for this bundle.
touch "$APP"

echo "✅ Adaptive icon installed in $APP"
