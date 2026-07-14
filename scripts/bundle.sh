#!/bin/bash
# Build a release binary and assemble Vitals.app (ad-hoc signed).
# Usage: scripts/bundle.sh [--install]   (--install copies to /Applications)
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Vitals.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Vitals "$APP/Contents/MacOS/Vitals"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Quit a running copy before replacing it.
    pkill -x Vitals 2>/dev/null || true
    rm -rf /Applications/Vitals.app
    cp -R "$APP" /Applications/Vitals.app
    echo "Installed to /Applications/Vitals.app"
    open /Applications/Vitals.app
fi
