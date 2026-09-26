#!/bin/zsh
# Runs the full-screen window unit tests (boringNotchTests/FullscreenWindows*Tests.swift)
# without launching the app.
# Upstream's test target is hosted inside Boring Notch, so `xcodebuild test`
# would start a second copy next to the installed one; here the code under test
# is compiled with the tests into a small XCTest runner, as
# tools/test-clipboard.sh does for the clipboard.
#
# Usage: tools/test-fullscreen-windows.sh
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
cd "$repo"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
platform="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer"
work="$repo/build/fullscreen-windows-tests"
rm -rf "$work"
mkdir -p "$work"

sources=(
    boringNotch/extensions/FullscreenWindows.swift
)
classes=()
for test in boringNotchTests/FullscreenWindows*Tests.swift; do
    sed '/^@testable import boringNotch$/d' "$test" > "$work/${test:t}"
    classes+=("${test:t:r}.self")
done

cat > "$work/main.swift" <<SWIFT
import XCTest

var failures = 0
for testCase in [${(j:, :)classes}] as [XCTestCase.Type] {
    let suite = XCTestSuite(forTestCaseClass: testCase)
    suite.run()
    failures += suite.testRun?.totalFailureCount ?? 0
}
print(failures == 0 ? "All full-screen window tests passed" : "\(failures) full-screen window test failure(s)")
exit(failures == 0 ? 0 : 1)
SWIFT

xcrun swiftc -target "$(uname -m)-apple-macos14.0" \
    -F "$platform/Library/Frameworks" -I "$platform/usr/lib" -L "$platform/usr/lib" \
    -Xlinker -rpath -Xlinker "$platform/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$platform/usr/lib" \
    -framework XCTest $sources "$work"/*.swift -o "$work/run"
"$work/run"
