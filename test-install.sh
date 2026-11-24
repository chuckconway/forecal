#!/bin/bash
# Checks install.sh in throwaway folders. It never touches /Applications,
# ~/Applications, or the app registry.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL="$PWD/install.sh"
export FORECAL_SKIP_LSREGISTER=1
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "install.sh: $1" >&2; exit 1; }

# A fake bundle: an identifier, plus a marker file to tell copies apart.
make_app() {
    mkdir -p "$1/Contents"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" "$1/Contents/Info.plist" >/dev/null
    echo "$3" > "$1/Contents/marker"
}
marker() { cat "$1/Contents/marker" 2>/dev/null || true; }

BUILT="$WORK/build/ForeCal.app"
make_app "$BUILT" com.cconway.ForeCal new-build

# 1. Another app is at the install path: refuse, and change nothing.
D="$WORK/foreign"; F="$WORK/foreign-former"
make_app "$D/ForeCal.app" com.apple.Safari.WebApp.SOMEONE-ELSE web-app
make_app "$F/ForeCal.app" com.cconway.ForeCal former-build
if FORECAL_INSTALL_DIR="$D" FORECAL_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null 2>&1; then
    fail "installed over a different app"
fi
[[ "$(marker "$D/ForeCal.app")" == web-app ]] || fail "the other app was changed"
[[ "$(marker "$F/ForeCal.app")" == former-build ]] || fail "a refused install still removed the former copy"

# 2. Our old build is at the install path: replace it.
D="$WORK/upgrade"
make_app "$D/ForeCal.app" com.cconway.ForeCal old-build
FORECAL_INSTALL_DIR="$D" FORECAL_FORMER_DIR="$WORK/none" "$INSTALL" "$BUILT" >/dev/null
[[ "$(marker "$D/ForeCal.app")" == new-build ]] || fail "our old build was not replaced"

# 3. Our copy in the former location goes; someone else's lookalike stays.
D="$WORK/move"; F="$WORK/former"
make_app "$F/ForeCal.app" com.cconway.ForeCal former-build
FORECAL_INSTALL_DIR="$D" FORECAL_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null
[[ ! -e "$F/ForeCal.app" ]] || fail "our copy in the former location was left behind"
[[ "$(marker "$D/ForeCal.app")" == new-build ]] || fail "the move did not install"
make_app "$F/ForeCal.app" com.example.other someone-else
FORECAL_INSTALL_DIR="$D" FORECAL_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null
[[ "$(marker "$F/ForeCal.app")" == someone-else ]] || fail "another app in the former location was removed"

# 4. The thing being installed isn't a ForeCal build: refuse.
make_app "$WORK/build/Other/ForeCal.app" com.example.other other
if FORECAL_INSTALL_DIR="$WORK/empty" FORECAL_FORMER_DIR="$WORK/none" "$INSTALL" "$WORK/build/Other/ForeCal.app" >/dev/null 2>&1; then
    fail "installed a bundle that isn't ForeCal"
fi
[[ ! -e "$WORK/empty/ForeCal.app" ]] || fail "a refused bundle landed"

echo "install.sh: 4 checks passed"
