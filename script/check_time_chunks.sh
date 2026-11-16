#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/cache"
swift build --disable-sandbox --cache-path .build/cache --product FocusCoreChecks
BUILD_DIR="$(swift build --disable-sandbox --cache-path .build/cache --show-bin-path)"
CHECK_BINARY="$(mktemp -t FocusNestChunkChecks)"
trap 'rm -f "$CHECK_BINARY"' EXIT
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
    Tests/StoreChecks/TimeChunkChecks.swift \
    Sources/FocusNest/Stores/TrackerStore.swift \
    "$BUILD_DIR"/FocusCore.build/*.o -o "$CHECK_BINARY"
"$CHECK_BINARY"
