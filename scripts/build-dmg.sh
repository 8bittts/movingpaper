#!/usr/bin/env bash
#
# build-dmg.sh — Build, sign, and package MovingPaper.app as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh                  # Full pipeline: build + sign + DMG + notarize
#   ./scripts/build-dmg.sh --build-only     # Build and assemble .app only (no DMG)
#   ./scripts/build-dmg.sh --local          # Build + DMG, skip notarization
#   ./scripts/build-dmg.sh --unsigned       # Ad-hoc sign only (no Developer ID)
#
# Environment variables (all optional):
#   MOVINGPAPER_CODESIGN_IDENTITY   Override signing identity
#   MOVINGPAPER_NOTARY_PROFILE      Keychain notarization profile name
#   MOVINGPAPER_VERSION             Override version string
#   MOVINGPAPER_BUILD               Override build number

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────

APP_NAME="MovingPaper"
BUNDLE_ID="com.8bittts.moving-paper"
GITHUB_REPO="8bittts/moving-paper"
MIN_MACOS="15.0"
DIST_DIR="dist"
BUILD_DIR="build"
DMG_VOLUME_NAME="Moving Paper"
DMG_WINDOW_WIDTH=540
DMG_WINDOW_HEIGHT=400
DMG_ICON_SIZE=128

# ── Flags ────────────────────────────────────────────────────────────────────

BUILD_ONLY=false
LOCAL_MODE=false
UNSIGNED=false

for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=true ;;
        --local)      LOCAL_MODE=true ;;
        --unsigned)   UNSIGNED=true ;;
        *)            echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33mWARN:\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }
step()  { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }

# ── Version ──────────────────────────────────────────────────────────────────

PLIST_FILE="Sources/${APP_NAME}/Resources/Info.plist"

# Auto-increment version: 0.001 -> 0.002 -> ... -> 0.999 -> 1.001
# Reads current version from Info.plist, bumps by .001, writes back.
# Override with MOVINGPAPER_VERSION to skip auto-increment.
bump_version() {
    local current="$1"
    # Split on '.'
    local major="${current%%.*}"
    local minor="${current#*.}"
    # Remove leading zeros for arithmetic, then re-pad to 3 digits
    local minor_num=$((10#$minor))
    minor_num=$((minor_num + 1))
    if [ "$minor_num" -ge 1000 ]; then
        major=$((major + 1))
        minor_num=1
    fi
    printf "%d.%03d" "$major" "$minor_num"
}

if [ -n "${MOVINGPAPER_VERSION:-}" ]; then
    VERSION="$MOVINGPAPER_VERSION"
else
    CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_FILE")
    VERSION=$(bump_version "$CURRENT_VERSION")
    # Write bumped version back to Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_FILE"
fi

CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_FILE")
BUILD_NUMBER="${MOVINGPAPER_BUILD:-$((CURRENT_BUILD + 1))}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_FILE"

info "Moving Paper v${VERSION} (build ${BUILD_NUMBER})"

# ── Signing identity ────────────────────────────────────────────────────────

resolve_signing_identity() {
    if [ "$UNSIGNED" = true ]; then
        CODESIGN_IDENTITY="-"
        warn "Ad-hoc signing (--unsigned)"
        return
    fi

    if [ -n "${MOVINGPAPER_CODESIGN_IDENTITY:-}" ]; then
        CODESIGN_IDENTITY="$MOVINGPAPER_CODESIGN_IDENTITY"
        step "Using override identity: $CODESIGN_IDENTITY"
        return
    fi

    # Search for Developer ID in keychain
    local identity
    identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed 's/.*"\(.*\)".*/\1/' || true)

    if [ -n "$identity" ]; then
        CODESIGN_IDENTITY="$identity"
        step "Found identity: $CODESIGN_IDENTITY"
    else
        CODESIGN_IDENTITY="-"
        warn "No Developer ID found — falling back to ad-hoc signing"
    fi
}

resolve_signing_identity

# ── Notarization ─────────────────────────────────────────────────────────────

NOTARY_PROFILE="${MOVINGPAPER_NOTARY_PROFILE:-YEN-Notarization}"

can_notarize() {
    [ "$BUILD_ONLY" = false ] && [ "$LOCAL_MODE" = false ] && [ "$UNSIGNED" = false ] \
        && [ "$CODESIGN_IDENTITY" != "-" ] \
        && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null
}

# ── Step 1: Clean ────────────────────────────────────────────────────────────

info "Cleaning previous artifacts"
/bin/rm -rf "$DIST_DIR" "$BUILD_DIR"
mkdir -p "$DIST_DIR" "$BUILD_DIR"

# ── Step 1b: Fetch yt-dlp if missing ─────────────────────────────────────────

YTDLP_DIR="tools/yt-dlp"
YTDLP_BIN="${YTDLP_DIR}/yt-dlp"
if [ ! -f "$YTDLP_BIN" ]; then
    info "Downloading yt-dlp"
    mkdir -p "$YTDLP_DIR"
    curl -sL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" -o "$YTDLP_BIN"
    chmod +x "$YTDLP_BIN"
    step "Downloaded yt-dlp $(${YTDLP_BIN} --version)"
else
    step "yt-dlp present ($(${YTDLP_BIN} --version))"
fi

# ── Step 2: Generate app icon ────────────────────────────────────────────────

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

# ── Step 3: Build release binary ─────────────────────────────────────────────

info "Building release binary"
swift build -c release 2>&1 | tail -5
step "Build complete"

BINARY_PATH=".build/release/${APP_NAME}"
if [ ! -f "$BINARY_PATH" ]; then
    fail "Binary not found at $BINARY_PATH"
fi

# ── Step 4: Assemble app bundle ──────────────────────────────────────────────

info "Assembling ${APP_NAME}.app"

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

FRAMEWORKS_DIR="${CONTENTS}/Frameworks"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# Copy binary
cp "$BINARY_PATH" "$MACOS_DIR/${APP_NAME}"
step "Copied binary"

# Copy resource bundle (SPM generates this)
RESOURCE_BUNDLE=".build/release/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    step "Copied resource bundle"
fi

# Copy icon
if [ -f "$ICNS_FILE" ]; then
    cp "$ICNS_FILE" "$RESOURCES_DIR/${APP_NAME}.icns"
    step "Copied app icon"
fi

# Copy Sparkle framework
SPARKLE_SOURCE="tools/sparkle/Sparkle.framework"
if [ -d "$SPARKLE_SOURCE" ]; then
    ditto "$SPARKLE_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
    step "Copied Sparkle.framework"
fi

# Copy yt-dlp binary
YTDLP_SOURCE="tools/yt-dlp/yt-dlp"
if [ -f "$YTDLP_SOURCE" ]; then
    cp "$YTDLP_SOURCE" "${RESOURCES_DIR}/yt-dlp"
    chmod +x "${RESOURCES_DIR}/yt-dlp"
    step "Copied yt-dlp"
else
    warn "yt-dlp not found at ${YTDLP_SOURCE} — YouTube features will be disabled"
fi

# Generate Info.plist
cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Moving Paper</string>
    <key>CFBundleDisplayName</key>
    <string>Moving Paper</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright $(date +%Y) 8BIT. MIT License.</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL:-https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY:-0Gr0zoQweDjkOPIj9VSnNZzlTSTrnHlHnAIcwaXbmkU=}</string>
    <key>SUScheduledCheckInterval</key>
    <integer>3600</integer>
</dict>
</plist>
PLIST
step "Generated Info.plist"

step "App bundle assembled at ${APP_BUNDLE}"

if [ "$BUILD_ONLY" = true ]; then
    info "Build complete (--build-only). App at: ${APP_BUNDLE}"
    exit 0
fi

# ── Step 5: Code sign ───────────────────────────────────────────────────────

info "Signing ${APP_NAME}.app"

sign_with_retry() {
    local target="$1"
    local attempt=0
    local max_attempts=5

    while [ $attempt -lt $max_attempts ]; do
        if codesign --force --options runtime --timestamp \
            --sign "$CODESIGN_IDENTITY" \
            --entitlements MovingPaper.entitlements \
            "$target" 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        step "Retry $attempt/$max_attempts (timestamp server may be slow)..."
        sleep 2
    done
    fail "Signing failed after $max_attempts attempts"
}

# Sign Sparkle framework nested components first (inside-out)
SPARKLE_FW="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    for nested in \
        "$SPARKLE_FW/Versions/B/XPCServices"/*.xpc \
        "$SPARKLE_FW/Versions/B/Autoupdate.app" \
        "$SPARKLE_FW/Versions/B/Autoupdate" \
        "$SPARKLE_FW/Versions/B/Updater.app"; do
        [ -e "$nested" ] || continue
        codesign --force --options runtime --timestamp \
            --sign "$CODESIGN_IDENTITY" "$nested" 2>&1
    done
    codesign --force --options runtime --timestamp \
        --sign "$CODESIGN_IDENTITY" "$SPARKLE_FW" 2>&1
    step "Signed Sparkle.framework"
fi

# Sign yt-dlp binary (must be signed for notarization)
YTDLP_BUNDLE="${APP_BUNDLE}/Contents/Resources/yt-dlp"
if [ -f "$YTDLP_BUNDLE" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$CODESIGN_IDENTITY" "$YTDLP_BUNDLE" 2>&1
    step "Signed yt-dlp"
fi

# Sign main app bundle
sign_with_retry "$APP_BUNDLE"
step "Signed ${APP_NAME}.app"

# Verify signature
codesign --verify --strict --verbose=2 "$APP_BUNDLE" 2>&1 | head -3
step "Signature verified"

# ── Step 6: Create DMG ──────────────────────────────────────────────────────

info "Creating DMG"

DMG_STAGING="${BUILD_DIR}/dmg-staging"
DMG_RW="${BUILD_DIR}/${APP_NAME}-rw.dmg"
DMG_FINAL="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_BG_SOURCE="brand/moving-paper-dmg-background.png"
DMG_BG_OPAQUE="${BUILD_DIR}/dmg-background-opaque.png"

# DMG layout constants (background is 2062x1080, window is ~660x400)
DMG_WIN_LEFT=200
DMG_WIN_TOP=200
DMG_WIN_WIDTH=660
DMG_WIN_HEIGHT=400
DMG_WIN_RIGHT=$((DMG_WIN_LEFT + DMG_WIN_WIDTH))
DMG_WIN_BOTTOM=$((DMG_WIN_TOP + DMG_WIN_HEIGHT))
DMG_WIN_RIGHT_JIGGLE=$((DMG_WIN_RIGHT - 10))
DMG_WIN_BOTTOM_JIGGLE=$((DMG_WIN_BOTTOM - 10))

mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/Moving Paper.app"
ln -s /Applications "$DMG_STAGING/Applications"

# Prepare background image (must be opaque RGB -- Finder silently fails with RGBA)
if [ -f "$DMG_BG_SOURCE" ]; then
    # Flatten alpha to black background and resize to match DMG window (2x for Retina)
    sips -s format png --setProperty formatOptions 100 "$DMG_BG_SOURCE" --out "$DMG_BG_OPAQUE" --resampleWidth $((DMG_WIN_WIDTH * 2)) >/dev/null 2>&1
    # Remove alpha channel via JPEG round-trip (sips -s hasAlpha is broken)
    sips -s format jpeg "$DMG_BG_OPAQUE" --out "${DMG_BG_OPAQUE%.png}.jpg" >/dev/null 2>&1
    sips -s format png "${DMG_BG_OPAQUE%.png}.jpg" --out "$DMG_BG_OPAQUE" >/dev/null 2>&1
    /bin/rm -f "${DMG_BG_OPAQUE%.png}.jpg"
    mkdir -p "$DMG_STAGING/.background"
    cp "$DMG_BG_OPAQUE" "$DMG_STAGING/.background/background.png"
    step "Prepared DMG background (opaque RGB)"
fi

# Create writable DMG (HFS+ for Finder layout persistence)
hdiutil create -srcfolder "$DMG_STAGING" \
    -volname "$DMG_VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -ov "$DMG_RW" \
    -quiet

# Mount for layout customization
DMG_MOUNT=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen -nobrowse 2>&1 | grep "/Volumes/" | /usr/bin/sed 's/.*\/Volumes/\/Volumes/')

if [ -n "$DMG_MOUNT" ]; then
    step "Mounted at ${DMG_MOUNT}"

    # Clean up metadata that interferes with Finder layout
    /bin/rm -rf "${DMG_MOUNT}/.fseventsd" 2>/dev/null || true
    /bin/rm -f "${DMG_MOUNT}/.metadata_never_index" 2>/dev/null || true
    /bin/rm -f "${DMG_MOUNT}/.VolumeIcon.icns" 2>/dev/null || true

    # Hide .background folder
    if [ -d "${DMG_MOUNT}/.background" ]; then
        chflags hidden "${DMG_MOUNT}/.background" 2>/dev/null || true
        SetFile -a V "${DMG_MOUNT}/.background" 2>/dev/null || true
    fi

    # Build background AppleScript command
    BG_CMD=""
    if [ -f "${DMG_MOUNT}/.background/background.png" ]; then
        BG_CMD='set background picture of theViewOptions to file ".background:background.png"'
    fi

    # Configure DMG window appearance with background and icon positions
    DMG_MOUNT_NAME=$(basename "$DMG_MOUNT")
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
        set position of item "Moving Paper.app" of container window to {200, 200}
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

    # Unmount
    hdiutil detach "$DMG_MOUNT" -quiet || hdiutil detach "$DMG_MOUNT" -force -quiet || true
fi

# Compress to final DMG
hdiutil convert "$DMG_RW" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL" \
    -quiet
/bin/rm -f "$DMG_RW"
step "Compressed DMG: ${DMG_FINAL}"

# Sign DMG
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_FINAL"
    step "Signed DMG"
fi

# ── Step 7: Notarize ────────────────────────────────────────────────────────

if can_notarize; then
    info "Notarizing DMG"
    xcrun notarytool submit "$DMG_FINAL" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    # Staple the notarization ticket
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

# ── Step 8: Checksum ────────────────────────────────────────────────────────

info "Generating checksum"
CHECKSUM=$(shasum -a 256 "$DMG_FINAL" | awk '{print $1}')
echo "$CHECKSUM  $(basename "$DMG_FINAL")" > "${DIST_DIR}/${APP_NAME}-${VERSION}.sha256"
step "SHA-256: ${CHECKSUM}"

# ── Step 8b: Create local git tag ────────────────────────────────────────────

# Tag locally so appcast release notes can diff between versions
if ! git tag -l "v${VERSION}" | grep -q "v${VERSION}"; then
    git tag "v${VERSION}" 2>/dev/null || true
    step "Tagged v${VERSION}"
fi

# ── Step 9: Update README download link ─────────────────────────────────────

info "Updating README.md download link"
DMG_FILENAME="${APP_NAME}-${VERSION}.dmg"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DMG_FILENAME}"

if [ -f README.md ]; then
    # Update the download link block (multi-line between markers)
    python3 -c "
import re, sys
text = open('README.md').read()
text = re.sub(
    r'<!-- download-link -->.*?<!-- /download-link -->',
    '<!-- download-link -->\n[**Download Moving Paper v${VERSION}**](${DOWNLOAD_URL})\n<!-- /download-link -->',
    text, flags=re.DOTALL)
text = re.sub(
    r'<!-- version-badge -->.*?<!-- /version-badge -->',
    '<!-- version-badge -->v${VERSION}<!-- /version-badge -->',
    text)
open('README.md', 'w').write(text)
"
    step "README.md updated with v${VERSION} download link"
fi

# ── Step 10: Generate appcast ────────────────────────────────────────────────

APPCAST_SCRIPT="$(dirname "$0")/generate-appcast.sh"
if [ -f "$APPCAST_SCRIPT" ] && [ "$BUILD_ONLY" = false ]; then
    info "Generating appcast"
    bash "$APPCAST_SCRIPT"
    step "Appcast generated: ${DIST_DIR}/appcast.xml"
else
    if [ "$BUILD_ONLY" = true ]; then
        step "Skipping appcast (--build-only)"
    else
        warn "Appcast script not found at ${APPCAST_SCRIPT}"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

DMG_SIZE=$(du -h "$DMG_FINAL" | awk '{print $1}')

echo ""
info "Build complete"
echo "  App:      ${APP_BUNDLE}"
echo "  DMG:      ${DMG_FINAL} (${DMG_SIZE})"
echo "  Checksum: ${DIST_DIR}/${APP_NAME}-${VERSION}.sha256"
echo "  Download: ${DOWNLOAD_URL}"
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "  Signed:   ${CODESIGN_IDENTITY}"
fi
echo ""
