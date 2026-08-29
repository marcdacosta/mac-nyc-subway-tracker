#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
app_bundle="$repo_root/.build/NYC Subway.app"

case "$app_bundle" in
    */.build/NYC\ Subway.app) ;;
    *)
        echo "Refusing to replace unexpected app path: $app_bundle" >&2
        exit 1
        ;;
esac

swift build --package-path "$repo_root" -c release --product Nostrand
binary_dir=$(swift build --package-path "$repo_root" -c release --show-bin-path)

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$repo_root/App/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$binary_dir/Nostrand" "$app_bundle/Contents/MacOS/Nostrand"

codesign --force --sign - "$app_bundle"

echo "$app_bundle"
