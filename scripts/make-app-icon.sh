#!/usr/bin/env bash
# Renders Resources/Icons/AppIcon.svg into AppIcon.icns. Needs librsvg (brew install librsvg).
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" Resources/Icons/AppIcon.svg -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/Icons/AppIcon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o Resources/Icons/AppIcon.icns
rm -rf "$(dirname "$ICONSET")"
