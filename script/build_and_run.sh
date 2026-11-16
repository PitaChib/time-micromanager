#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FocusNest"
DISPLAY_NAME="Time Micromanager"
BUNDLE_ID="local.focusnest.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$APP_NAME"

cd "$ROOT_DIR"
case "$MODE" in
    run|--build-only|--verify|--debug|--logs|--telemetry) ;;
    *) echo "usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
BUILD_VERSION="$(date -u +%Y%m%d%H%M%S)"
if [[ "$MODE" != "--build-only" ]]; then
    # Ask the running app to save before terminating it.
    if pgrep -x "$APP_NAME" >/dev/null; then
        /usr/bin/osascript -e 'tell application id "local.focusnest.app" to quit'
        for attempt in {1..20}; do
            if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi
            sleep 0.25
        done
        if pgrep -x "$APP_NAME" >/dev/null; then
            echo "FocusNest is still running. Close its open dialogs and try again." >&2
            exit 1
        fi
    fi
fi

CONFIGURATION="release"
if [[ "$MODE" == "--debug" ]]; then CONFIGURATION="debug"; fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/cache"
swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" -c "$CONFIGURATION" --product FocusNest
BUILD_BINARY="$(swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY.next"
mv -f "$APP_BINARY.next" "$APP_BINARY"
chmod +x "$APP_BINARY"

ICON_WORK="$ROOT_DIR/.build/FocusNest.iconset"
if [[ ! -f "$APP_CONTENTS/Resources/FocusNest.icns" || "$ROOT_DIR/Assets/time-micromanager.png" -nt "$APP_CONTENTS/Resources/FocusNest.icns" || "$ROOT_DIR/script/generate_icon.swift" -nt "$APP_CONTENTS/Resources/FocusNest.icns" ]]; then
    mkdir -p "$ICON_WORK"
    cp "$ROOT_DIR/Assets/time-micromanager.png" "$ROOT_DIR/.build/FocusNest-icon.png"
    for pixels in 16 32 128 256 512; do
        sips -z "$pixels" "$pixels" "$ROOT_DIR/.build/FocusNest-icon.png" --out "$ICON_WORK/icon_${pixels}x${pixels}.png" >/dev/null
        retina=$((pixels * 2))
        sips -z "$retina" "$retina" "$ROOT_DIR/.build/FocusNest-icon.png" --out "$ICON_WORK/icon_${pixels}x${pixels}@2x.png" >/dev/null
    done
    python3 "$ROOT_DIR/script/package_icon.py" "$ICON_WORK" "$APP_CONTENTS/Resources/FocusNest.icns"
fi

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$DISPLAY_NAME</string>
<key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>$BUILD_VERSION</string>
<key>CFBundleIconFile</key><string>FocusNest</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/CREDITS.md" "$APP_CONTENTS/Resources/"
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"

# Refresh the sharing archive on every release build so it cannot lag behind
# the app opened by Run. Replace the previous ZIP only after packaging succeeds.
if [[ "$CONFIGURATION" == "release" ]]; then
    ARCHIVE="$ROOT_DIR/dist/Time-Micromanager.zip"
    ARCHIVE_TEMP="$(mktemp -d "$ROOT_DIR/dist/.package.XXXXXX")"
    trap 'rm -rf "$ARCHIVE_TEMP"' EXIT
    /usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$ARCHIVE_TEMP/$APP_NAME.zip"
    mv -f "$ARCHIVE_TEMP/$APP_NAME.zip" "$ARCHIVE"
    echo "Share $ARCHIVE (build $BUILD_VERSION)"
fi
case "$MODE" in
    run) /usr/bin/open -n "$APP_BUNDLE" ;;
    --build-only) echo "Built $APP_BUNDLE" ;;
    --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "FocusNest is running." ;;
    --debug) lldb -- "$APP_BINARY" ;;
    --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "FocusNest"' ;;
    --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.focusnest.app"' ;;
    *) echo "usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
