#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
version=$(plutil -extract CFBundleShortVersionString raw "$repo_root/App/Info.plist")
product="MacNYCSubwayTracker"
app_name="Mac NYC Subway Tracker.app"
release_root="$repo_root/.build/release-bundle"
app_bundle="$release_root/$app_name"
archives_dir="$repo_root/.build/releases"
archive="$archives_dir/Mac-NYC-Subway-Tracker-v$version-universal.zip"
checksum="$archive.sha256"
arm_scratch="$repo_root/.build/release-arm64"
intel_scratch="$repo_root/.build/release-x86_64"
signing_identity=${CODE_SIGN_IDENTITY:--}
notary_profile=${NOTARY_PROFILE:-}

case "$release_root" in
    */.build/release-bundle) ;;
    *)
        echo "Refusing to replace unexpected release path: $release_root" >&2
        exit 1
        ;;
esac

case "$archive" in
    */.build/releases/Mac-NYC-Subway-Tracker-v*-universal.zip) ;;
    *)
        echo "Refusing to replace unexpected archive path: $archive" >&2
        exit 1
        ;;
esac

if [ -n "$notary_profile" ] && [ "$signing_identity" = "-" ]; then
    echo "NOTARY_PROFILE requires a Developer ID CODE_SIGN_IDENTITY." >&2
    exit 1
fi

swift build \
    --package-path "$repo_root" \
    --scratch-path "$arm_scratch" \
    -c release \
    --triple arm64-apple-macosx13.0 \
    --product "$product"
arm_binary_dir=$(swift build \
    --package-path "$repo_root" \
    --scratch-path "$arm_scratch" \
    -c release \
    --triple arm64-apple-macosx13.0 \
    --show-bin-path)

swift build \
    --package-path "$repo_root" \
    --scratch-path "$intel_scratch" \
    -c release \
    --triple x86_64-apple-macosx13.0 \
    --product "$product"
intel_binary_dir=$(swift build \
    --package-path "$repo_root" \
    --scratch-path "$intel_scratch" \
    -c release \
    --triple x86_64-apple-macosx13.0 \
    --show-bin-path)

rm -rf "$release_root"
mkdir -p "$app_bundle/Contents/MacOS" "$archives_dir"
cp "$repo_root/App/Info.plist" "$app_bundle/Contents/Info.plist"
lipo -create \
    "$arm_binary_dir/$product" \
    "$intel_binary_dir/$product" \
    -output "$app_bundle/Contents/MacOS/$product"

if [ "$signing_identity" = "-" ]; then
    codesign --force --sign - "$app_bundle"
else
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$app_bundle"
fi

codesign --verify --deep --strict "$app_bundle"

rm -f "$archive" "$checksum"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$app_bundle" "$archive"

if [ -n "$notary_profile" ]; then
    xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app_bundle"
    xcrun stapler validate "$app_bundle"
    rm -f "$archive"
    ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$app_bundle" "$archive"
fi

(cd "$archives_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")")

echo "$archive"
echo "$checksum"
