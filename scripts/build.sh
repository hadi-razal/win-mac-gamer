#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build --configuration release --disable-sandbox --build-system native
app="$PWD/dist/LocalPlay.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/LocalPlay "$app/Contents/MacOS/LocalPlay"
cp .build/release/localplayctl "$app/Contents/MacOS/localplayctl"
cp scripts/Info.plist "$app/Contents/Info.plist"
cp docs/THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --sign - "$app"
print "Built: $app"
