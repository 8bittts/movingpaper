#!/usr/bin/env bash
#
# build-dmg.sh — Build, sign, and package MovingPaper.app as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh                  # Build current metadata into a signed DMG
#   ./scripts/build-dmg.sh --build-only     # Build and assemble .app only (no DMG)
#   ./scripts/build-dmg.sh --local          # Build + DMG, skip notarization
#   ./scripts/build-dmg.sh --unsigned       # Ad-hoc sign only (no Developer ID)
#
# Environment variables (all optional):
#   MOVINGPAPER_CODESIGN_IDENTITY   Override signing identity
#   MOVINGPAPER_NOTARY_PROFILE      Keychain notarization profile name
#   MOVINGPAPER_VERSION             Override version string for the packaged app
#   MOVINGPAPER_BUILD               Override build number for the packaged app
#   SPARKLE_FEED_URL                Override Sparkle appcast URL
#   SPARKLE_PUBLIC_ED_KEY           Override Sparkle EdDSA public key

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="MovingPaper"
BUNDLE_ID="com.8bittts.moving-paper"
GITHUB_REPO="8bittts/movingpaper"
BUILD_DIR="build"
DMG_VOLUME_NAME="MovingPaper"
DMG_ICON_SIZE=128
NOTARY_PROFILE="${MOVINGPAPER_NOTARY_PROFILE:-YEN-Notarization}"
SOURCE_PLIST="sources/Resources/Info.plist"
SPARKLE_SOURCE="tools/sparkle/Sparkle.framework"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-0Gr0zoQweDjkOPIj9VSnNZzlTSTrnHlHnAIcwaXbmkU=}"

BUILD_ONLY=false
LOCAL_MODE=false
UNSIGNED=false

for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=true ;;
        --local)      LOCAL_MODE=true ;;
        --unsigned)   UNSIGNED=true ;;
        *)            echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }
step()  { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }

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

resolve_signing_identity() {
    if [ "$UNSIGNED" = true ]; then
        CODESIGN_IDENTITY="-"
        warn "Ad-hoc signing (--unsigned)"
        return
    fi

    if [ -n "${MOVINGPAPER_CODESIGN_IDENTITY:-}" ]; then
        CODESIGN_IDENTITY="$MOVINGPAPER_CODESIGN_IDENTITY"
        step "Using override identity: ${CODESIGN_IDENTITY}"
        return
    fi

    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed 's/.*"\(.*\)".*/\1/' || true)"

    if [ -n "$identity" ]; then
        CODESIGN_IDENTITY="$identity"
        step "Found identity: ${CODESIGN_IDENTITY}"
    else
        CODESIGN_IDENTITY="-"
        warn "No Developer ID found — falling back to ad-hoc signing"
    fi
}

codesign_base_args() {
    CODESIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY")
    if [ "$CODESIGN_IDENTITY" != "-" ]; then
        CODESIGN_ARGS+=(--options runtime)
        CODESIGN_ARGS+=(--timestamp)
    fi
}

sign_target() {
    local target="$1"
    local with_entitlements="${2:-false}"

    local args=("${CODESIGN_ARGS[@]}")
    if [ "$with_entitlements" = true ]; then
        args+=(--entitlements "MovingPaper.entitlements")
    fi

    codesign "${args[@]}" "$target"
}

sign_with_retry() {
    local target="$1"
    local attempt=0
    local max_attempts=5

    while [ $attempt -lt $max_attempts ]; do
        if sign_target "$target" true 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        step "Retry $attempt/$max_attempts (timestamp server may be slow)..."
        sleep 2
    done
    fail "Signing failed after $max_attempts attempts"
}

can_notarize() {
    [ "$BUILD_ONLY" = false ] \
        && [ "$LOCAL_MODE" = false ] \
        && [ "$UNSIGNED" = false ] \
        && [ "$CODESIGN_IDENTITY" != "-" ] \
        && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}

[ -f "$SOURCE_PLIST" ] || fail "Source Info.plist not found at ${SOURCE_PLIST}"
[ -d "$SPARKLE_SOURCE" ] || fail "Sparkle.framework missing at ${SPARKLE_SOURCE}"

CURRENT_VERSION="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE_PLIST"
)"
CURRENT_BUILD="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SOURCE_PLIST"
)"

VERSION="${MOVINGPAPER_VERSION:-$CURRENT_VERSION}"
BUILD_NUMBER="${MOVINGPAPER_BUILD:-$CURRENT_BUILD}"

info "Packaging MovingPaper v${VERSION} (build ${BUILD_NUMBER})"

resolve_signing_identity
codesign_base_args

info "Cleaning previous artifacts"
if [ -d "$BUILD_DIR" ]; then
    for item in "$BUILD_DIR"/*; do
        [ -e "$item" ] || continue
        case "$item" in
            *.png) ;;
            *)     /bin/rm -rf "$item" ;;
        esac
    done
fi
mkdir -p "$BUILD_DIR"

info "Generating app icon"
swift scripts/generate-app-icon.swift

ICONSET_DIR="${BUILD_DIR}/${APP_NAME}.iconset"
ICNS_FILE="${BUILD_DIR}/${APP_NAME}.icns"
if [ -d "$ICONSET_DIR" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
    step "Created ${ICNS_FILE}"
else
    warn "Iconset not found — skipping .icns generation"
fi

info "Building release binary"
swift build -c release
step "Build complete"

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="${BIN_DIR}/${APP_NAME}"
RESOURCE_BUNDLE="${BIN_DIR}/${APP_NAME}_${APP_NAME}.bundle"

[ -f "$BINARY_PATH" ] || fail "Binary not found at ${BINARY_PATH}"

info "Assembling ${APP_NAME}.app"

APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
FRAMEWORKS_DIR="${CONTENTS}/Frameworks"
INFO_PLIST="${CONTENTS}/Info.plist"

/bin/rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/${APP_NAME}"
step "Copied binary"

if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    step "Copied resource bundle"
fi

if [ -f "$ICNS_FILE" ]; then
    cp "$ICNS_FILE" "$RESOURCES_DIR/${APP_NAME}.icns"
    step "Copied app icon"
fi

ditto "$SPARKLE_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
step "Copied Sparkle.framework"

cp "$SOURCE_PLIST" "$INFO_PLIST"
plist_set "$INFO_PLIST" "CFBundleIdentifier" string "$BUNDLE_ID"
plist_set "$INFO_PLIST" "CFBundleExecutable" string "$APP_NAME"
plist_set "$INFO_PLIST" "CFBundleName" string "$APP_NAME"
plist_set "$INFO_PLIST" "CFBundlePackageType" string "APPL"
plist_set "$INFO_PLIST" "CFBundleShortVersionString" string "$VERSION"
plist_set "$INFO_PLIST" "CFBundleVersion" string "$BUILD_NUMBER"
plist_set "$INFO_PLIST" "CFBundleIconFile" string "$APP_NAME"
plist_set "$INFO_PLIST" "NSPrincipalClass" string "NSApplication"
# Packaged builds skip Sparkle's permission prompt and opt into stronger
# archive verification before extraction.
plist_set "$INFO_PLIST" "SUEnableAutomaticChecks" bool true
plist_set "$INFO_PLIST" "SUFeedURL" string "$SPARKLE_FEED_URL"
plist_set "$INFO_PLIST" "SUPublicEDKey" string "$SPARKLE_PUBLIC_ED_KEY"
plist_set "$INFO_PLIST" "SUScheduledCheckInterval" integer 3600
plist_set "$INFO_PLIST" "SUVerifyUpdateBeforeExtraction" bool true
plist_set "$INFO_PLIST" "SURequireSignedFeed" bool true
step "Generated Info.plist"

step "App bundle assembled at ${APP_BUNDLE}"

if [ "$BUILD_ONLY" = true ]; then
    info "Build complete (--build-only). App at: ${APP_BUNDLE}"
    exit 0
fi

info "Signing ${APP_NAME}.app"

SPARKLE_FW="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    for nested in \
        "$SPARKLE_FW/Versions/B/XPCServices"/*.xpc \
        "$SPARKLE_FW/Versions/B/Autoupdate.app" \
        "$SPARKLE_FW/Versions/B/Autoupdate" \
        "$SPARKLE_FW/Versions/B/Updater.app"; do
        [ -e "$nested" ] || continue
        sign_target "$nested" false >/dev/null
    done
    sign_target "$SPARKLE_FW" false >/dev/null
    step "Signed Sparkle.framework"
fi

sign_with_retry "$APP_BUNDLE"
step "Signed ${APP_NAME}.app"

codesign --verify --strict --verbose=2 "$APP_BUNDLE" 2>&1 | head -3
step "Signature verified"

info "Creating DMG"

DMG_STAGING="${BUILD_DIR}/dmg-staging"
DMG_RW="${BUILD_DIR}/${APP_NAME}-rw.dmg"
DMG_FINAL="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_BG_SOURCE="build/movingpaper-dmg-background.png"
DMG_BG_OPAQUE="${BUILD_DIR}/dmg-background-opaque.png"
DMG_WIN_LEFT=200
DMG_WIN_TOP=200
DMG_WIN_WIDTH=660
DMG_WIN_HEIGHT=400
DMG_WIN_RIGHT=$((DMG_WIN_LEFT + DMG_WIN_WIDTH))
DMG_WIN_BOTTOM=$((DMG_WIN_TOP + DMG_WIN_HEIGHT))
DMG_WIN_RIGHT_JIGGLE=$((DMG_WIN_RIGHT - 10))
DMG_WIN_BOTTOM_JIGGLE=$((DMG_WIN_BOTTOM - 10))

mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGING/Applications"

if [ -f "$DMG_BG_SOURCE" ]; then
    sips -s format png --setProperty formatOptions 100 "$DMG_BG_SOURCE" --out "$DMG_BG_OPAQUE" --resampleWidth $((DMG_WIN_WIDTH * 2)) >/dev/null 2>&1
    sips -s format jpeg "$DMG_BG_OPAQUE" --out "${DMG_BG_OPAQUE%.png}.jpg" >/dev/null 2>&1
    sips -s format png "${DMG_BG_OPAQUE%.png}.jpg" --out "$DMG_BG_OPAQUE" >/dev/null 2>&1
    /bin/rm -f "${DMG_BG_OPAQUE%.png}.jpg"
    mkdir -p "$DMG_STAGING/.background"
    cp "$DMG_BG_OPAQUE" "$DMG_STAGING/.background/background.png"
    step "Prepared DMG background (opaque RGB)"
fi

hdiutil create -srcfolder "$DMG_STAGING" \
    -volname "$DMG_VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -ov "$DMG_RW" \
    -quiet

DMG_MOUNT="$(
    hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen -nobrowse 2>&1 \
        | grep "/Volumes/" \
        | /usr/bin/sed 's/.*\/Volumes/\/Volumes/'
)"

if [ -n "$DMG_MOUNT" ]; then
    step "Mounted at ${DMG_MOUNT}"

    /bin/rm -rf "${DMG_MOUNT}/.fseventsd" 2>/dev/null || true
    /bin/rm -f "${DMG_MOUNT}/.metadata_never_index" 2>/dev/null || true
    /bin/rm -f "${DMG_MOUNT}/.VolumeIcon.icns" 2>/dev/null || true

    if [ -d "${DMG_MOUNT}/.background" ]; then
        chflags hidden "${DMG_MOUNT}/.background" 2>/dev/null || true
        SetFile -a V "${DMG_MOUNT}/.background" 2>/dev/null || true
    fi

    BG_CMD=""
    if [ -f "${DMG_MOUNT}/.background/background.png" ]; then
        BG_CMD='set background picture of theViewOptions to file ".background:background.png"'
    fi

    DMG_MOUNT_NAME="$(basename "$DMG_MOUNT")"
    osascript <<EOF >/dev/null 2>&1 || true
set dmgDiskName to "$DMG_MOUNT_NAME"
tell application "Finder"
    tell disk dmgDiskName
        open
        delay 1
        tell container window
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {${DMG_WIN_LEFT}, ${DMG_WIN_TOP}, ${DMG_WIN_RIGHT}, ${DMG_WIN_BOTTOM}}
        end tell
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to ${DMG_ICON_SIZE}
        set text size of theViewOptions to 14
        $BG_CMD
        set position of item "${APP_NAME}.app" of container window to {200, 200}
        set position of item "Applications" of container window to {460, 200}
        try
            set position of item ".background" of container window to {330, 900}
        end try
        try
            set position of item ".fseventsd" of container window to {330, 950}
        end try
        try
            set selection to {}
        end try
        close
        delay 1
        open
        tell container window
            set statusbar visible to false
            set bounds to {${DMG_WIN_LEFT}, ${DMG_WIN_TOP}, ${DMG_WIN_RIGHT_JIGGLE}, ${DMG_WIN_BOTTOM_JIGGLE}}
        end tell
        delay 1
        tell container window
            set bounds to {${DMG_WIN_LEFT}, ${DMG_WIN_TOP}, ${DMG_WIN_RIGHT}, ${DMG_WIN_BOTTOM}}
        end tell
        delay 1
        close
    end tell
end tell
EOF
    step "Applied DMG layout with background"
    hdiutil detach "$DMG_MOUNT" -quiet || hdiutil detach "$DMG_MOUNT" -force -quiet || true
fi

hdiutil convert "$DMG_RW" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL" \
    -quiet
/bin/rm -f "$DMG_RW"
step "Compressed DMG: ${DMG_FINAL}"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_FINAL"
    step "Signed DMG"
fi

if can_notarize; then
    info "Notarizing DMG"
    xcrun notarytool submit "$DMG_FINAL" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    attempt=0
    while [ $attempt -lt 10 ]; do
        if xcrun stapler staple "$DMG_FINAL" 2>&1; then
            step "Notarization ticket stapled"
            break
        fi
        attempt=$((attempt + 1))
        step "Staple retry $attempt/10..."
        sleep 10
    done
else
    if [ "$LOCAL_MODE" = true ]; then
        step "Skipping notarization (--local)"
    elif [ "$UNSIGNED" = true ]; then
        step "Skipping notarization (--unsigned)"
    else
        warn "Notarization skipped — no keychain profile '${NOTARY_PROFILE}' found"
        warn "To set up: xcrun notarytool store-credentials ${NOTARY_PROFILE}"
    fi
fi

info "Generating checksum"
CHECKSUM="$(shasum -a 256 "$DMG_FINAL" | awk '{print $1}')"
echo "${CHECKSUM}  $(basename "$DMG_FINAL")" > "${BUILD_DIR}/${APP_NAME}-${VERSION}.sha256"
step "SHA-256: ${CHECKSUM}"

APPCAST_SCRIPT="$(dirname "$0")/generate-appcast.sh"
if [ -f "$APPCAST_SCRIPT" ]; then
    info "Generating appcast"
    bash "$APPCAST_SCRIPT"
    step "Appcast generated: ${BUILD_DIR}/appcast.xml"
else
    warn "Appcast script not found at ${APPCAST_SCRIPT}"
fi

DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/$(basename "$DMG_FINAL")"
DMG_SIZE="$(du -h "$DMG_FINAL" | awk '{print $1}')"

echo ""
info "Build complete"
echo "  App:      ${APP_BUNDLE}"
echo "  DMG:      ${DMG_FINAL} (${DMG_SIZE})"
echo "  Checksum: ${BUILD_DIR}/${APP_NAME}-${VERSION}.sha256"
echo "  Download: ${DOWNLOAD_URL}"
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "  Signed:   ${CODESIGN_IDENTITY}"
else
    echo "  Signed:   ad-hoc"
fi
echo ""
