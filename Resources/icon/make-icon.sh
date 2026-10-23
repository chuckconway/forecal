#!/bin/bash
# Renders the icon SVGs: AppIcon.svg to Resources/AppIcon.icns (and the README
# copy), and both SVGs to the light and dark images the About screen shows.
# Needs Google Chrome, which renders SVG gradients and clipping faithfully.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# render <svg> <png>: a 1024 x 1024 PNG with a transparent background.
render() {
    printf '<html><body style="margin:0;background:transparent">%s</body></html>' "$(cat "$1")" > "$WORK/page.html"
    "$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
        --window-size=1024,1024 --screenshot="$2" "file://$WORK/page.html" 2>/dev/null
}

render AppIcon.svg "$WORK/light.png"
render AppIcon-Dark.svg "$WORK/dark.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/light.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/light.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o ../AppIcon.icns
cp "$WORK/light.png" ../../docs/icon.png

# The About screen shows the icon at 72 pt, so 256 px covers 2x displays.
sips -z 256 256 "$WORK/light.png" --out ../AboutIcon-Light.png >/dev/null
sips -z 256 256 "$WORK/dark.png" --out ../AboutIcon-Dark.png >/dev/null
echo "Wrote Resources/AppIcon.icns and Resources/AboutIcon-{Light,Dark}.png"
