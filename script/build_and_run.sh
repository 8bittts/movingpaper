#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-run}"
APP_NAME="MovingPaper"
BUNDLE_ID="com.8bittts.moving-paper"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PLIST="${REPO_ROOT}/sources/Resources/Info.plist"
LOCAL_RUN_DIR="${REPO_ROOT}/build/local-run"
APP_BUNDLE="${LOCAL_RUN_DIR}/${APP_NAME}.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_RESOURCES="${APP_CONTENTS}/Resources"
APP_FRAMEWORKS="${APP_CONTENTS}/Frameworks"
APP_BINARY="${APP_MACOS}/${APP_NAME}"
INFO_PLIST="${APP_CONTENTS}/Info.plist"
ICONSET_DIR="${REPO_ROOT}/build/${APP_NAME}.iconset"
ICNS_FILE="${REPO_ROOT}/build/${APP_NAME}.icns"
SPARKLE_SOURCE="${REPO_ROOT}/tools/sparkle/Sparkle.framework"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/8bittts/movingpaper/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-0Gr0zoQweDjkOPIj9VSnNZzlTSTrnHlHnAIcwaXbmkU=}"

plist_set() {
    local plist="$1"
    local key="$2"
    local type="$3"
    local value="$4"

    if /usr/libexec/PlistBuddy -c "Print :${key}" "$plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$plist"
    else
        /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "$plist"
    fi
}

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$REPO_ROOT"
swift build

BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="${BUILD_BIN_DIR}/${APP_NAME}"
RESOURCE_BUNDLE="${BUILD_BIN_DIR}/${APP_NAME}_${APP_NAME}.bundle"

[ -f "$BUILD_BINARY" ] || { echo "Missing app binary at ${BUILD_BINARY}" >&2; exit 1; }
[ -f "$SOURCE_PLIST" ] || { echo "Missing source Info.plist at ${SOURCE_PLIST}" >&2; exit 1; }
[ -d "$SPARKLE_SOURCE" ] || { echo "Missing Sparkle.framework at ${SPARKLE_SOURCE}" >&2; exit 1; }

swift scripts/generate-app-icon.swift >/dev/null
if [ -d "$ICONSET_DIR" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
fi

/bin/rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

if [ -f "$ICNS_FILE" ]; then
    cp "$ICNS_FILE" "$APP_RESOURCES/${APP_NAME}.icns"
fi

ditto "$SPARKLE_SOURCE" "$APP_FRAMEWORKS/Sparkle.framework"
cp "$SOURCE_PLIST" "$INFO_PLIST"

plist_set "$INFO_PLIST" "CFBundleIdentifier" string "$BUNDLE_ID"
plist_set "$INFO_PLIST" "CFBundleExecutable" string "$APP_NAME"
plist_set "$INFO_PLIST" "CFBundleName" string "$APP_NAME"
plist_set "$INFO_PLIST" "CFBundlePackageType" string "APPL"
plist_set "$INFO_PLIST" "CFBundleIconFile" string "$APP_NAME"
plist_set "$INFO_PLIST" "NSPrincipalClass" string "NSApplication"
# Local staged app bundles mirror release updater defaults so Sparkle behavior
# matches distribution builds during manual verification.
plist_set "$INFO_PLIST" "SUEnableAutomaticChecks" bool true
plist_set "$INFO_PLIST" "SUFeedURL" string "$SPARKLE_FEED_URL"
plist_set "$INFO_PLIST" "SUPublicEDKey" string "$SPARKLE_PUBLIC_ED_KEY"
plist_set "$INFO_PLIST" "SUScheduledCheckInterval" integer 3600
plist_set "$INFO_PLIST" "SUVerifyUpdateBeforeExtraction" bool true
plist_set "$INFO_PLIST" "SURequireSignedFeed" bool true

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"${APP_NAME}\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"${BUNDLE_ID}\""
        ;;
    --verify|verify)
        open_app
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
