#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh path/to/OneLine.app}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_NAME="OneLine-${VERSION}.dmg"

STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "OneLine" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING"

echo "Created $DMG_NAME"
