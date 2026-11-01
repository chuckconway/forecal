#!/bin/bash
# Builds ForeCal.app into ./build.
#   --install   copy it to ~/Applications and launch it
#   --release   sign with Developer ID, notarize, and write build/ForeCal.zip
#   --snapshot <dir>, --hover-test <file>   run the snapshot tools (see Snapshot.swift)
set -euo pipefail
cd "$(dirname "$0")"

# Optional: the name of a self-signed code-signing identity, in an untracked file.
LOCAL_IDENTITY=$(cat .signing-identity 2>/dev/null || true)
NOTARY_PROFILE="ForeCal"  # created once with `xcrun notarytool store-credentials`

if [[ "${1:-}" == "--release" ]]; then
    # Universal, for Apple silicon and Intel. `swift build --arch` would do this
    # in one step but needs full Xcode, so build each and join them with lipo.
    swift build -c release --triple arm64-apple-macosx14.0
    swift build -c release --triple x86_64-apple-macosx14.0
    BINARY=.build/ForeCal-universal
    lipo -create -output "$BINARY" \
        .build/arm64-apple-macosx/release/ForeCal .build/x86_64-apple-macosx/release/ForeCal
else
    swift build -c release
    BINARY=.build/release/ForeCal
fi
APP=build/ForeCal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/ForeCal"
cp Resources/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/AboutIcon-*.png Resources/container-migration.plist "$APP/Contents/Resources/"

# Hardened runtime everywhere, so local builds run under the same rules as
# releases, sandbox included; the entitlements let it through to calendars,
# location, and the network.
sign() {
    codesign --force --options runtime --timestamp=none \
        --entitlements Resources/ForeCal.entitlements --sign "$1" "$APP"
}

if [[ "${1:-}" == "--release" ]]; then
    ./test.sh
    IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
    if [[ -z "$IDENTITY" ]]; then
        echo "No Developer ID Application certificate in the keychain." >&2
        exit 1
    fi
    # Notarization needs a secure timestamp, unlike local builds.
    codesign --force --options runtime --timestamp \
        --entitlements Resources/ForeCal.entitlements --sign "$IDENTITY" "$APP"
    ditto -c -k --keepParent "$APP" build/ForeCal.zip
    xcrun notarytool submit build/ForeCal.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    # Re-zip so the download carries the stapled ticket and opens offline.
    rm build/ForeCal.zip
    ditto -c -k --keepParent "$APP" build/ForeCal.zip
    spctl --assess --type execute --verbose "$APP"
    echo "Release ready: build/ForeCal.zip"
    exit 0
fi

# A stable identity keeps calendar and location permission across rebuilds;
# ad hoc signatures look like a new app to macOS every time.
if [[ -n "$LOCAL_IDENTITY" ]] && security find-identity -p codesigning | grep -q "$LOCAL_IDENTITY"; then
    sign "$LOCAL_IDENTITY"
else
    sign -
fi

# Snapshot tools write wherever they're told, which the sandbox blocks. They
# use sample data and never touch calendars or location, so run them from an
# unsandboxed copy made only for this.
if [[ "${1:-}" == "--snapshot" || "${1:-}" == "--hover-test" ]]; then
    TOOL=build/ForeCal-snapshot.app
    rm -rf "$TOOL"
    cp -R "$APP" "$TOOL"
    codesign --force --sign - "$TOOL"
    # --snapshot takes a directory, --hover-test a file.
    if [[ "$1" == "--snapshot" ]]; then mkdir -p "$2"; else mkdir -p "$(dirname "$2")"; fi
    "$TOOL/Contents/MacOS/ForeCal" "$1" "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    exit 0
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ForeCal || true
    # Launching while the old copy is still quitting fails with error -600.
    while pgrep -x ForeCal >/dev/null; do sleep 0.2; done
    mkdir -p ~/Applications
    rm -rf ~/Applications/ForeCal.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/ForeCal.app
fi
