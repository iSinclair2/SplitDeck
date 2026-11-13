#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="${1:-0.1.0}"
release_dir="$project_dir/dist"

cd "$project_dir"
"$project_dir/scripts/build-app.sh"
mkdir -p "$release_dir"
rm -f \
  "$release_dir/SplitDeck-$version-macOS.zip" \
  "$release_dir/SplitDeck-$version-source.zip"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "$project_dir/SplitDeck.app" \
  "$release_dir/SplitDeck-$version-macOS.zip"

/usr/bin/zip -q -r "$release_dir/SplitDeck-$version-source.zip" . \
  -x '.build/*' 'dist/*' '*.app/*' '.git/*' '.swiftpm/*' '*.DS_Store' '*.mov' '*.zip' '*.xcuserstate' 'xcuserdata/*'

echo "$release_dir/SplitDeck-$version-macOS.zip"
echo "$release_dir/SplitDeck-$version-source.zip"
