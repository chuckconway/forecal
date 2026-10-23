#!/bin/bash
# Runs the tests. Extra arguments go to `swift test` (e.g. --filter NextUp).
set -euo pipefail
cd "$(dirname "$0")"

# With only the Command Line Tools installed, Swift Testing ships in a folder
# SwiftPM doesn't search, and XCTest isn't there at all. Full Xcode needs neither.
DEV=$(xcode-select -p)
if [[ "$DEV" == *CommandLineTools* ]]; then
    F="$DEV/Library/Developer/Frameworks"
    exec swift test --disable-xctest --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
fi
exec swift test "$@"
