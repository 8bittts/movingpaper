#!/usr/bin/env bash
#
# generate-appcast.sh — Generate a signed Sparkle appcast.xml for MovingPaper.
#
# Usage:
#   ./scripts/generate-appcast.sh
#
# Reads version/build from the built app bundle in build/, prepares embedded
# release notes for the current DMG, and generates a signed appcast.xml using
# Sparkle's generate_appcast tool.
#
# Environment:
#   MOVINGPAPER_APPCAST_DOWNLOAD_BASE   Override base URL for DMG download
#                                        (default: GitHub Releases)
#   SPARKLE_ED_KEYCHAIN_ACCOUNT         Keychain account name for the private
#                                        Ed25519 key (default: ed25519)
#   SPARKLE_ED_PRIVATE_KEY_FILE         Optional path to a private Ed25519 key
#                                        file for feed signing
#   SPARKLE_PRIVATE_ED_KEY              Optional private Ed25519 key string.
#                                        When set, this is piped to
#                                        generate_appcast via stdin.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Constants ────────────────────────────────────────────────────────────────

APP_NAME="MovingPaper"
GITHUB_REPO="8bittts/movingpaper"
APPCAST_TOOL="tools/sparkle/bin/generate_appcast"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

APP_BUNDLE="build/${APP_NAME}.app"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
OUTPUT="build/appcast.xml"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
step()  { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }

# ── Validate ─────────────────────────────────────────────────────────────────

[ -d "$APP_BUNDLE" ] || fail "App bundle not found at $APP_BUNDLE — run build-dmg.sh first"
[ -x "$APPCAST_TOOL" ] || fail "Sparkle generate_appcast tool not found at $APPCAST_TOOL"

# ── Extract metadata ─────────────────────────────────────────────────────────

VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$INFO_PLIST")"

DMG_FILENAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="build/${DMG_FILENAME}"

[ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH"

info "Generating signed appcast for MovingPaper v${VERSION} (build ${BUILD_NUMBER})"

# ── Download URL ─────────────────────────────────────────────────────────────

DOWNLOAD_BASE="${MOVINGPAPER_APPCAST_DOWNLOAD_BASE:-https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}}"
DOWNLOAD_PREFIX="${DOWNLOAD_BASE%/}/"
DOWNLOAD_URL="${DOWNLOAD_PREFIX}${DMG_FILENAME}"
step "Download URL: ${DOWNLOAD_URL}"

# ── Release notes (from git history) ────────────────────────────────────────

release_notes_html() {
    local ver="$1"
    local items="$2"
    cat <<HTML
<style>
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        padding: 16px 20px;
        line-height: 1.6;
        color: #1d1d1f;
    }
    h2 { font-size: 17px; font-weight: 600; margin: 0 0 14px 0; }
    ul { padding-left: 20px; margin: 0; }
    li { margin-bottom: 6px; font-size: 13px; }
    .footer { margin-top: 16px; font-size: 11px; color: #86868b; }
</style>
<h2>What's New</h2>
<ul>
$(printf '%b' "$items")</ul>
<p class="footer">MovingPaper ${ver} -- your desktop, alive.</p>
HTML
}

generate_release_notes() {
    local ver="$1"

    if [ -n "${SPARKLE_NOTES:-}" ]; then
        local items=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local cap
            cap=$(echo "$line" | awk '{$1=toupper(substr($1,1,1)) substr($1,2)} 1')
            items="${items}    <li>${cap}</li>\n"
        done <<< "$(printf '%b' "$SPARKLE_NOTES")"

        cat <<NOTES
$(release_notes_html "$ver" "$items")
NOTES
        return
    fi

    local prev_tag
    if [ -n "${SPARKLE_NOTES_SINCE:-}" ]; then
        prev_tag="$SPARKLE_NOTES_SINCE"
    else
        prev_tag=$(git tag --sort=-v:refname | grep '^v' | grep -vx "v${ver}" | head -1)
    fi

    local commits=""
    if [ -n "$prev_tag" ]; then
        commits=$(git log "${prev_tag}..HEAD" --pretty=format:"%s" --no-merges 2>/dev/null \
            | grep -v "^release:" \
            | grep -v "^chore:" \
            | grep -v "^ci:" \
            | grep -v "^docs:" \
            | grep -v "^style:" \
            | grep -v "^refactor:" \
            | grep -v "^test:" \
            | grep -v "^build:" \
            | grep -vi "^Update " \
            | grep -vi "remove tracked" \
            | grep -vi "gitignore" \
            | grep -vi "README" \
            | grep -vi "CLAUDE" \
            | grep -vi "AGENTS" \
            | grep -vi "appcast" \
            | grep -vi "sparkle" \
            | grep -vi "notariz" \
            | grep -vi "build script" \
            | grep -vi "build-dmg" \
            | grep -vi "codesign" \
            | head -6)
    fi

    if [ -z "$commits" ]; then
        commits="Bug fixes and performance improvements"
    fi

    local items=""
    while IFS= read -r msg; do
        [ -z "$msg" ] && continue
        local clean
        clean=$(echo "$msg" | sed 's/^[a-z]*: *//')
        clean=$(echo "$clean" | awk '{$1=toupper(substr($1,1,1)) substr($1,2)} 1')
        items="${items}    <li>${clean}</li>\n"
    done <<< "$commits"

    release_notes_html "$ver" "$items"
}

# ── Prepare archive staging directory ────────────────────────────────────────

ARCHIVES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/movingpaper-appcast.XXXXXX")"
cleanup() {
    rm -rf "$ARCHIVES_DIR"
}
trap cleanup EXIT

cp "$DMG_PATH" "${ARCHIVES_DIR}/${DMG_FILENAME}"
NOTES_FILE="${ARCHIVES_DIR}/${APP_NAME}-${VERSION}.html"
generate_release_notes "$VERSION" > "$NOTES_FILE"
step "Prepared release notes: ${NOTES_FILE}"

# ── Build generate_appcast command ──────────────────────────────────────────

GENERATE_CMD=(
    "$APPCAST_TOOL"
    --account "${SPARKLE_ED_KEYCHAIN_ACCOUNT:-ed25519}"
    --download-url-prefix "$DOWNLOAD_PREFIX"
    --embed-release-notes
    -o "$OUTPUT"
    "$ARCHIVES_DIR"
)

if [ -n "${SPARKLE_ED_PRIVATE_KEY_FILE:-}" ]; then
    GENERATE_CMD=(
        "$APPCAST_TOOL"
        --ed-key-file "${SPARKLE_ED_PRIVATE_KEY_FILE}"
        --download-url-prefix "$DOWNLOAD_PREFIX"
        --embed-release-notes
        -o "$OUTPUT"
        "$ARCHIVES_DIR"
    )
fi

# ── Generate signed appcast ─────────────────────────────────────────────────

if [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
    info "Generating signed appcast from stdin-provided Ed25519 key"
    printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "${GENERATE_CMD[@]}"
else
    info "Generating signed appcast"
    "${GENERATE_CMD[@]}"
fi

[ -f "$OUTPUT" ] || fail "Appcast generation failed: missing ${OUTPUT}"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$OUTPUT" 2>&1 && step "XML validated"
fi

REQUIRE_SIGNED_FEED="$("$PLIST_BUDDY" -c 'Print :SURequireSignedFeed' "$INFO_PLIST" 2>/dev/null || echo false)"
if [ "$REQUIRE_SIGNED_FEED" = "true" ]; then
    if grep -q "sparkle-signatures:" "$OUTPUT"; then
        step "Verified embedded Sparkle feed signature"
    else
        fail "Signed feed required, but ${OUTPUT} is missing Sparkle's embedded feed signature block"
    fi
fi

step "Appcast written to ${OUTPUT}"
step "Signed feed generation complete"
