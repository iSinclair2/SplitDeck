#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p "$project_dir/.build/cache/clang" "$project_dir/.build/cache/swiftpm"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/cache/swiftpm"
# Build for Apple silicon and Intel separately, then merge into one universal binary.
# (A single multi-arch `swift build` needs Xcode's build system; this works with the
# Command Line Tools too.)
binaries=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx14.0"
  scratch="$project_dir/.build/$arch"
  swift build -c release --triple "$triple" --scratch-path "$scratch"
  binaries+=("$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)/NowPlayingController")
done

app="$project_dir/SplitDeck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -f "$app/Contents/MacOS/NowPlayingController"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/SplitDeck"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.png" "$app/Contents/Resources/AppIcon.png"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
echo "$app"
