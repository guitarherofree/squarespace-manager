#!/usr/bin/env bash
# Renders branding/icon.svg into the app's icon set. Needs rsvg-convert (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."
SET="App/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" branding/icon.svg -o "$SET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) branding/icon.svg -o "$SET/icon_${size}x${size}@2x.png"
done
echo "Icons written to $SET"
