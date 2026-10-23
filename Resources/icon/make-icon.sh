#!/bin/bash
# Renders AppIcon.svg to Resources/AppIcon.icns. Needs Google Chrome, because
# the mark is stroked paths that simpler SVG renderers drop.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

printf '<html><body style="margin:0;background:transparent">%s</body></html>' "$(cat AppIcon.svg)" > "$WORK/icon.html"
"$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$WORK/icon-1024.png" "file://$WORK/icon.html" 2>/dev/null

ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o ../AppIcon.icns
cp "$WORK/icon-1024.png" ../../docs/icon.png
echo "Wrote Resources/AppIcon.icns"
