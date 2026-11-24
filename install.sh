#!/bin/bash
# Installs a built ForeCal.app into /Applications (or $FORECAL_INSTALL_DIR).
# build.sh --install calls this; test-install.sh checks it in throwaway folders.
#
# /Applications, not ~/Applications: menu-bar managers such as Dimble match an
# icon to its app through LaunchServices, and an app in ~/Applications was
# hidden with no way to reveal it. For the same reason the install leaves
# exactly one registered copy.
#
# It removes only a bundle it can prove is ForeCal, by CFBundleIdentifier. A
# file name proves nothing: Safari saves web apps in ~/Applications under
# ordinary names.
set -euo pipefail

APP="${1:?usage: install.sh <path to the built ForeCal.app>}"
DEST_DIR="${FORECAL_INSTALL_DIR:-/Applications}"
# Where earlier versions installed. A copy there is removed only if it's ours.
FORMER_DIR="${FORECAL_FORMER_DIR:-$HOME/Applications}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
OURS=com.cconway.ForeCal

bundle_id() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true
}

if [[ "$(bundle_id "$APP")" != "$OURS" ]]; then
    echo "$APP is not a ForeCal build; not installing it." >&2
    exit 1
fi

TARGET="$DEST_DIR/$(basename "$APP")"
FORMER="$FORMER_DIR/$(basename "$APP")"

# Decide everything before removing anything, so a refusal changes nothing.
if [[ -e "$TARGET" && "$(bundle_id "$TARGET")" != "$OURS" ]]; then
    echo "$TARGET is another app ($(bundle_id "$TARGET")); not replacing it." >&2
    exit 1
fi

if [[ "$FORMER" != "$TARGET" && -e "$FORMER" ]]; then
    if [[ "$(bundle_id "$FORMER")" == "$OURS" ]]; then
        rm -rf "$FORMER"
        echo "Removed $FORMER (where earlier versions installed)."
    else
        echo "Left $FORMER alone: it isn't ForeCal."
    fi
fi
mkdir -p "$DEST_DIR"
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"
echo "Installed to $TARGET"

# One registered copy: forget every other path macOS holds for this identifier
# (build folders, the former location), then register the installed one.
if [[ -z "${FORECAL_SKIP_LSREGISTER:-}" && -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -dump 2>/dev/null \
        | awk -v id="$OURS" '/^-{20,}/{if (blk ~ ("identifier: +" id "\n")) print blk; blk=""; next} {blk = blk "\n" $0}' \
        | sed -n -E 's/^path: +(.*) \(0x[0-9a-f]+\)$/\1/p' \
        | while IFS= read -r registered; do
            [[ "$registered" == "$TARGET" ]] || "$LSREGISTER" -u "$registered" 2>/dev/null || true
        done
    "$LSREGISTER" -f "$TARGET"
    echo "Registered $TARGET as the only copy."
fi
