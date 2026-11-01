#!/bin/bash
# Renders the Mac App Store screenshots (2880 x 1800) into build/appstore-screenshots,
# from fresh snapshot-mode images of the panel with sample data. Needs Google Chrome.
set -euo pipefail
cd "$(dirname "$0")/../.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUT=build/appstore-screenshots
rm -rf "$OUT"
mkdir -p "$OUT"

./build.sh --snapshot "$WORK" >/dev/null

# page <file> <background> <headline> <subhead> <img>...: one screenshot, the
# text on the left and the images on the right, at 1440 x 900 points and 2x.
page() {
    local file=$1 background=$2 headline=$3 subhead=$4
    shift 4
    local images=""
    for image in "$@"; do images+="<img src=\"$WORK/$image\">"; done
    cat > "$WORK/page.html" <<HTML
<html><head><style>
  body { margin: 0; width: 1440px; height: 900px; background: $background;
         font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #fff;
         display: flex; align-items: center; justify-content: center; gap: 96px; overflow: hidden; }
  .text { width: 600px; }
  h1 { font-size: 60px; line-height: 1.05; letter-spacing: -1.5px; margin: 0 0 20px; }
  p { font-size: 28px; line-height: 1.35; margin: 0; opacity: .92; }
  .shots { display: flex; gap: 40px; align-items: center; }
  img { width: 340px; border-radius: 14px; box-shadow: 0 24px 60px rgba(0,0,0,.35); }
</style></head><body>
  <div class="text"><h1>$headline</h1><p>$subhead</p></div><div class="shots">$images</div>
</body></html>
HTML
    "$CHROME" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files \
        --force-device-scale-factor=2 --window-size=1440,900 \
        --screenshot="$OUT/$file" "file://$WORK/page.html" 2>/dev/null
}

SKY="linear-gradient(180deg, #3d8bff, #8fc3ff)"
NIGHT="linear-gradient(180deg, #0f1f45, #23396e)"
page 1-glance.png "$SKY" "Your day, at a glance" \
    "Events, weather, and when to leave, right in your menu bar." panel-light.png
page 2-dark.png "$NIGHT" "Leave on time" \
    "Drive times with traffic, and one click to join a call." panel-dark.png
page 3-private.png "$SKY" "Private by design" \
    "No account, no server, no tracking. Your calendars stay on your Mac." about-light.png

sips -g pixelWidth -g pixelHeight "$OUT"/*.png | grep -v pixelHeight | paste - - | awk '{print $1, $3}'
