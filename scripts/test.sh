#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build --build-tests --disable-sandbox --build-system native
# XCTest directly avoids a test-discovery hang in this host's Swift 6.4 preview toolchain.
binary_dir="$(swift build --show-bin-path --disable-sandbox --build-system native)"
xcrun xctest "$binary_dir/LocalPlayPackageTests.xctest"
