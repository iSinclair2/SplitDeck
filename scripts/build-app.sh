#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p "$project_dir/.build/cache/clang" "$project_dir/.build/cache/swiftpm"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/cache/swiftpm"
swift build -c release --scratch-path "$project_dir/.build"

app="$project_dir/SplitDeck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -f "$app/Contents/MacOS/NowPlayingController"
cp ".build/release/NowPlayingController" "$app/Contents/MacOS/SplitDeck"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.png" "$app/Contents/Resources/AppIcon.png"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
echo "$app"
