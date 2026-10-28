#!/usr/bin/env bash
# Builds dist/MeetingRush.app from source.
# Env: BUNDLE_ID, CODESIGN_IDENTITY (default "-", ad-hoc), RELEASE=1 for a distributable build.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MeetingRush"
BUNDLE_ID="${BUNDLE_ID:-dev.meetingrush.MeetingRush}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/${APP_NAME}.app"

BUILD_FLAGS=(-c release)
SIGN_FLAGS=(--force --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID")
if [[ "${RELEASE:-}" == "1" ]]; then
    # Releases run on Intel too, and notarisation needs the hardened runtime and a secure timestamp. Under the
    # hardened runtime, calendar access needs its entitlement. Dev builds skip all of this so they build offline
    # and debuggers can attach.
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
    SIGN_FLAGS+=(--options runtime --entitlements Resources/MeetingRush.entitlements --timestamp)
fi

swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Icons/*.pdf Resources/Icons/AppIcon.icns "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" Resources/Info.plist > "$APP/Contents/Info.plist"

codesign "${SIGN_FLAGS[@]}" "$APP"
echo "Built $APP $VERSION (signing identity: $CODESIGN_IDENTITY${RELEASE:+, release})"
