#!/usr/bin/env bash
# Builds dist/MeetingRush.app from source.
# Env: BUNDLE_ID, CODESIGN_IDENTITY (default "-", ad-hoc), SWIFT_BUILD_FLAGS (Homebrew passes --disable-sandbox).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MeetingRush"
BUNDLE_ID="${BUNDLE_ID:-dev.meetingrush.MeetingRush}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/${APP_NAME}.app"
read -r -a BUILD_FLAGS <<< "${SWIFT_BUILD_FLAGS:-}"

swift build -c release ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --show-bin-path ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"})"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Icons/*.pdf Resources/Icons/AppIcon.icns "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" Resources/Info.plist > "$APP/Contents/Info.plist"

codesign --force --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
echo "Built $APP $VERSION (signing identity: $CODESIGN_IDENTITY)"
