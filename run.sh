#!/bin/bash
# Builds and launches WebcamView.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
echo "🚀 Launching WebcamView.app..."
open "build/WebcamView.app"
echo "✅ Launched. Look for the 🎥 icon in your menu bar."
