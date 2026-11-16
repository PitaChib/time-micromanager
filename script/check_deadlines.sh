#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
swift run --disable-sandbox --cache-path .build/cache DeadlineChecks
BUILD_DIR="$(swift build --disable-sandbox --cache-path .build/cache --show-bin-path)"
CHECK_BINARY="$(mktemp -t FocusNestDeadlineChecks)"
trap 'rm -f "$CHECK_BINARY"' EXIT
swiftc -parse-as-library -I "$BUILD_DIR/Modules" Tests/StoreChecks/DeadlineStoreChecks.swift \
    Sources/FocusNest/Stores/TrackerStore.swift Sources/FocusNest/Stores/DeadlineStore.swift \
    "$BUILD_DIR"/FocusCore.build/*.o -o "$CHECK_BINARY"
"$CHECK_BINARY"
