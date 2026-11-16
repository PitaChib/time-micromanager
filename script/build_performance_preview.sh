#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
swift build --disable-sandbox --cache-path .build/cache -c release --product FocusNest
BUILD_DIR="$(swift build --disable-sandbox --cache-path .build/cache -c release --show-bin-path)"
PREVIEW="$PWD/.build/FocusNestTest.app"
mkdir -p "$PREVIEW/Contents/MacOS"
swiftc -O -parse-as-library -I "$BUILD_DIR/Modules" Tests/Performance/Preview.swift \
    Sources/FocusNest/Stores/*.swift Sources/FocusNest/Views/*.swift \
    "$BUILD_DIR"/FocusCore.build/*.o -o "$PREVIEW/Contents/MacOS/FocusNestTest"
cat > "$PREVIEW/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>FocusNestTest</string><key>CFBundleIdentifier</key><string>local.focusnest.testpreview</string><key>CFBundleName</key><string>FocusNestTest</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
codesign --force --sign - "$PREVIEW"
echo "$PREVIEW"
