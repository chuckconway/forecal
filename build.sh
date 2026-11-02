#!/bin/bash
# Builds ForeCal.app into ./build.
#   --install   copy it to ~/Applications and launch it
#   --release   sign with Developer ID, notarize, and write build/ForeCal.zip
#   --appstore  sign for the Mac App Store and write build/ForeCal.pkg
#   --snapshot <dir>, --hover-test <file>   run the snapshot tools (see Snapshot.swift)
set -euo pipefail
cd "$(dirname "$0")"

# Optional: the name of a self-signed code-signing identity, in an untracked file.
LOCAL_IDENTITY=$(cat .signing-identity 2>/dev/null || true)
NOTARY_PROFILE="ForeCal"  # created once with `xcrun notarytool store-credentials`
# The Mac App Store provisioning profile, downloaded from the developer site (untracked).
APPSTORE_PROFILE="AppStore.provisionprofile"

if [[ "${1:-}" == "--release" || "${1:-}" == "--appstore" ]]; then
    ./test.sh
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
# Every upload to the App Store needs a higher build number; the commit count
# on main only goes up.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/AboutIcon-*.png Resources/container-migration.plist "$APP/Contents/Resources/"

# The first identity in the keychain whose name starts with $1, or nothing.
identity() {
    security find-identity -v | { grep -o "\"$1[^\"]*\"" || true; } | head -1 | tr -d '"'
}

# Hardened runtime everywhere, so local builds run under the same rules as
# releases, sandbox included; the entitlements let it through to calendars,
# location, and the network.
sign() {
    codesign --force --options runtime --timestamp=none \
        --entitlements Resources/ForeCal.entitlements --sign "$1" "$APP"
}

if [[ "${1:-}" == "--release" ]]; then
    IDENTITY=$(identity "Developer ID Application: ")
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

if [[ "${1:-}" == "--appstore" ]]; then
    APP_IDENTITY=$(identity "Apple Distribution: ")
    # The Mac Installer Distribution certificate's name in the keychain.
    PKG_IDENTITY=$(identity "3rd Party Mac Developer Installer: ")
    if [[ -z "$APP_IDENTITY" || -z "$PKG_IDENTITY" ]]; then
        echo "Needs Apple Distribution and Mac Installer Distribution certificates in the keychain." >&2
        exit 1
    fi
    if [[ ! -f "$APPSTORE_PROFILE" ]]; then
        echo "Needs the Mac App Store provisioning profile at $APPSTORE_PROFILE." >&2
        exit 1
    fi
    TEAM=$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$APP_IDENTITY")
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)
    PROFILE_PLIST=build/profile.plist
    security cms -D -i "$APPSTORE_PROFILE" > "$PROFILE_PLIST"
    PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST")
    if [[ "$PROFILE_APP_ID" != "$TEAM.$BUNDLE_ID" ]]; then
        echo "The provisioning profile is for $PROFILE_APP_ID, not $TEAM.$BUNDLE_ID." >&2
        exit 1
    fi
    cp "$APPSTORE_PROFILE" "$APP/Contents/embedded.provisionprofile"
    # The App Store also wants the app and team identifiers that Xcode would add.
    ENTITLEMENTS=build/appstore.entitlements
    cp Resources/ForeCal.entitlements "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.application-identifier string $TEAM.$BUNDLE_ID" \
        -c "Add :com.apple.developer.team-identifier string $TEAM" \
        "$ENTITLEMENTS"
    # A downloaded profile carries the quarantine attribute, which the App Store
    # rejects anywhere in the app (error 91109). Clear all attributes before signing.
    xattr -cr "$APP"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$APP_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    productbuild --component "$APP" /Applications --sign "$PKG_IDENTITY" build/ForeCal.pkg
    pkgutil --check-signature build/ForeCal.pkg
    # Check what the App Store will see: nothing in the package may be quarantined.
    EXPANDED=build/pkg-check
    rm -rf "$EXPANDED"
    pkgutil --expand-full build/ForeCal.pkg "$EXPANDED"
    if xattr -r "$EXPANDED" | grep -q com.apple.quarantine; then
        echo "Quarantined files in the package:" >&2
        xattr -r "$EXPANDED" | grep com.apple.quarantine >&2
        exit 1
    fi
    rm -rf "$EXPANDED"
    echo "App Store build ready: build/ForeCal.pkg (upload it with Transporter)"
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
