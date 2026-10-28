#!/usr/bin/env bash
# Zips dist/MeetingRush.app into dist/MeetingRush-<version>.zip for a GitHub Release, notarising it first
# when NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID are set. Prints the zip's SHA-256 for the cask.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/MeetingRush.app"
ZIP="dist/MeetingRush-${VERSION}.zip"

codesign --verify --strict "$APP"

if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    ditto -c -k --keepParent "$APP" "dist/notarize.zip"
    xcrun notarytool submit "dist/notarize.zip" \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
    xcrun stapler staple "$APP"
    rm "dist/notarize.zip"
else
    echo "Notarisation skipped: no App Store Connect API key configured."
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | cut -d' ' -f1
