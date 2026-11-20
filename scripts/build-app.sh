#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"
swift build --disable-sandbox -c release
bin_dir="$(swift build --disable-sandbox -c release --show-bin-path)"

mkdir -p dist
staging="$(mktemp -d dist/.build-app.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/MacTileBar.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp scripts/Info.plist "$bundle/Contents/Info.plist"
install -m 755 "$bin_dir/MacTileBar" "$bundle/Contents/MacOS/MacTileBar"
install -m 644 .build/checkouts/TOMLDecoder/LICENSE.md "$bundle/Contents/Resources/TOMLDecoder-LICENSE.md"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"

destination="$PWD/dist/MacTileBar.app"
/usr/bin/ditto "$bundle" "$destination"
codesign --verify --strict "$destination"
printf '%s\n' "$destination"
