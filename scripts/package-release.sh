#!/usr/bin/env bash
# Zips dist/MeetingRush.app into dist/MeetingRush-<version>.zip for a GitHub Release and prints its SHA-256.
# Notarises first when NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID are all set, and fails if only some are.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/MeetingRush.app"
ZIP="dist/MeetingRush-${VERSION}.zip"

codesign --verify --strict "$APP"

MISSING=()
for name in NOTARY_KEY_PATH NOTARY_KEY_ID NOTARY_ISSUER_ID; do
    [[ -n "${!name:-}" ]] || MISSING+=("$name")
done
if (( ${#MISSING[@]} > 0 && ${#MISSING[@]} < 3 )); then
    echo "Notarisation is partly configured; missing ${MISSING[*]}" >&2
    exit 1
fi

if (( ${#MISSING[@]} == 0 )); then
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
