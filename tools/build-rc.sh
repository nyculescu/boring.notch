#!/bin/zsh
# Builds a release-candidate-style build of this branch: stamped with a version
# derived from upstream's nearest release tag, archived in Release and signed to
# run locally, so it can be installed for every account on this Mac.
#
# Usage: tools/build-rc.sh [--install] [--dmg] [--working-tree]
#   --install       replace /Applications/Boring Notch.app and launch the new build
#   --dmg           also write a disk image into build/rc
#   --working-tree  include uncommitted changes (default: the committed HEAD only)
set -euo pipefail

install=false
make_dmg=false
working_tree=false
for arg in "$@"; do
    case "$arg" in
        --install) install=true ;;
        --dmg) make_dmg=true ;;
        --working-tree) working_tree=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

repo=$(git rev-parse --show-toplevel)
cd "$repo"
out="$repo/build/rc"
src="$out/src"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
mkdir -p "$out"

# Version: upstream's nearest release tag plus this commit, e.g. 2.8-rc.1+local.3f2a9c1.
tag=$(git describe --tags --abbrev=0 --match 'v*' HEAD)
base_version=${tag#v}
suffix="local.$(git rev-parse --short=7 HEAD)"
if $working_tree && [[ -n "$(git status --porcelain)" ]]; then
    suffix="$suffix.dirty"
fi
version="$base_version+$suffix"

# Build number: the build upstream shipped for that tag plus the commits since it
# (e.g. 282.4), so the updater only offers official builds that are really newer.
tag_build=$(git show origin/main:updater/appcast.xml 2>/dev/null | python3 -c '
import re, sys
want = sys.argv[1]
for item in re.findall(r"<item>(.*?)</item>", sys.stdin.read(), re.S):
    short = re.search(r"<sparkle:shortVersionString>\s*([^<]+?)\s*<", item)
    build = re.search(r"<sparkle:version>\s*([0-9]+)\s*<", item)
    if short and build and short.group(1) == want:
        print(build.group(1))
        break
' "$base_version" || true)
if [[ -z "$tag_build" ]]; then
    tag_build=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);.*/\1/p' boringNotch.xcodeproj/project.pbxproj | head -1)
fi
build_number="$tag_build.$(git rev-list --count "$tag..HEAD")"

echo "Building Boring Notch $version ($build_number)"

# Build from a clean export so stamping never touches your checkout.
rm -rf "$src"
mkdir -p "$src"
if $working_tree; then
    git ls-files -z --cached --others --exclude-standard \
        | while IFS= read -r -d '' file; do [[ -e "$file" ]] && printf '%s\0' "$file"; done \
        | tar --null -T - -cf - | tar -xf - -C "$src"
else
    git archive HEAD | tar -xf - -C "$src"
fi
python3 "$src/.github/scripts/stamp_version.py" \
    --pbxproj "$src/boringNotch.xcodeproj/project.pbxproj" \
    --version "$version" \
    --build-number "$build_number"

archive="$out/boringNotch.xcarchive"
log="$out/archive.log"
rm -rf "$archive"
if ! xcodebuild archive \
    -project "$src/boringNotch.xcodeproj" \
    -scheme boringNotch \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    -derivedDataPath "$out/DerivedData" \
    -onlyUsePackageVersionsFromResolvedFile \
    ONLY_ACTIVE_ARCH=NO > "$log" 2>&1; then
    grep -E "error:" "$log" | sort -u | head -20 >&2 || true
    echo "Archive failed; full log: $log" >&2
    exit 1
fi

# Without a signing certificate the build is ad-hoc signed. Ad-hoc code has no
# Team ID, so hardened runtime's library validation would reject the embedded
# frameworks at launch; re-sign the app itself with that one check relaxed.
app="$archive/Products/Applications/Boring Notch.app"
entitlements="$out/entitlements.plist"
codesign -d --entitlements - --xml "$app" > "$entitlements" 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$entitlements" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$entitlements"
codesign --force --sign - --options runtime --entitlements "$entitlements" \
    --generate-entitlement-der --timestamp=none "$app" 2>/dev/null
codesign --verify --deep --strict "$app"

result="$out/Boring Notch.app"
rm -rf "$result"
ditto "$app" "$result"
echo "Built: $result"

if $make_dmg; then
    staging="$out/dmg"
    dmg="$out/Boring Notch $version.dmg"
    rm -rf "$staging" "$dmg"
    mkdir -p "$staging"
    ditto "$result" "$staging/Boring Notch.app"
    ln -s /Applications "$staging/Applications"
    hdiutil create -quiet -volname "Boring Notch $version" -srcfolder "$staging" -format UDZO "$dmg"
    rm -rf "$staging"
    echo "Disk image: $dmg"
fi

if $install; then
    dest="/Applications/Boring Notch.app"
    if pgrep -x "Boring Notch" >/dev/null; then
        pkill -x "Boring Notch" || true
        for _ in {1..20}; do pgrep -x "Boring Notch" >/dev/null || break; sleep 0.5; done
    fi
    if [[ -e "$dest" ]]; then
        # Earlier local builds are simply replaced; anything else (an official
        # build) goes to the Trash so it can be restored.
        if codesign -dv "$dest" 2>&1 | grep -q "Signature=adhoc"; then
            rm -rf "$dest"
        else
            trash "$dest"
        fi
    fi
    ditto "$result" "$dest"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest"
    open "$dest"
    echo "Installed and launched: $dest"
fi
