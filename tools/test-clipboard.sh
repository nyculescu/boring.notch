#!/bin/zsh
# Runs the clipboard unit tests (boringNotchTests/Clipboard*Tests.swift) without
# launching the app. Upstream's test target is hosted inside Boring Notch, so
# `xcodebuild test` would start a second copy next to the installed one; here
# the code under test is compiled with the tests into a small XCTest runner.
#
# Usage: tools/test-clipboard.sh
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
cd "$repo"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
platform="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer"
work="$repo/build/clipboard-tests"
rm -rf "$work"
mkdir -p "$work"

sources=(
    boringNotch/components/Clipboard/ClipboardItem.swift
    boringNotch/components/Clipboard/ClipboardPasteboardReader.swift
    boringNotch/components/Clipboard/ClipboardHistoryStore.swift
)
classes=()
for test in boringNotchTests/Clipboard*Tests.swift; do
    sed '/^@testable import boringNotch$/d' "$test" > "$work/${test:t}"
    classes+=("${test:t:r}.self")
done

cat > "$work/main.swift" <<EOF
import XCTest

var failures = 0
for testCase in [${(j:, :)classes}] as [XCTestCase.Type] {
    let suite = XCTestSuite(forTestCaseClass: testCase)
    suite.run()
    failures += suite.testRun?.totalFailureCount ?? 0
}
print(failures == 0 ? "All clipboard tests passed" : "\(failures) clipboard test failure(s)")
exit(failures == 0 ? 0 : 1)
EOF

xcrun swiftc -target "$(uname -m)-apple-macos14.0" \
    -F "$platform/Library/Frameworks" -I "$platform/usr/lib" -L "$platform/usr/lib" \
    -Xlinker -rpath -Xlinker "$platform/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$platform/usr/lib" \
    -framework XCTest $sources "$work"/*.swift -o "$work/run"
"$work/run"
