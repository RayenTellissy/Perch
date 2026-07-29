#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Perch"
APP_DIR="dist/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist")
DMG_PATH="dist/$APP_NAME-$VERSION.dmg"
STAGING="dist/dmg-staging"

if [ ! -d "$APP_DIR" ]; then
    echo "Missing $APP_DIR — run scripts/build-app.sh first" >&2
    exit 1
fi

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

rm -rf "$STAGING"
echo "Built $DMG_PATH"
