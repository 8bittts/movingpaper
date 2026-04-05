#!/usr/bin/env bash
#
# generate-appcast.sh — Generate a Sparkle appcast.xml for Moving Paper.
#
# Usage:
#   ./scripts/generate-appcast.sh
#
# Reads version/build from the built app bundle in dist/, signs the DMG
# with Sparkle's EdDSA tool, and outputs dist/appcast.xml.
#
# Environment:
#   MOVINGPAPER_APPCAST_DOWNLOAD_BASE   Override base URL for DMG download
#                                        (default: GitHub Releases)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Constants ────────────────────────────────────────────────────────────────

APP_NAME="MovingPaper"
GITHUB_REPO="8bittts/moving-paper"
SIGN_TOOL="tools/sparkle/bin/sign_update"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

APP_BUNDLE="dist/${APP_NAME}.app"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
OUTPUT="dist/appcast.xml"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
step()  { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }

# ── Validate ─────────────────────────────────────────────────────────────────

[ -d "$APP_BUNDLE" ] || fail "App bundle not found at $APP_BUNDLE — run build-dmg.sh first"
[ -x "$SIGN_TOOL" ] || fail "Sparkle sign_update tool not found at $SIGN_TOOL"

# ── Extract metadata ────────────────────────────────────────────────────────

VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$INFO_PLIST")"
MIN_MACOS="$("$PLIST_BUDDY" -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"

DMG_FILENAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="dist/${DMG_FILENAME}"

[ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH"

info "Generating appcast for Moving Paper v${VERSION} (build ${BUILD_NUMBER})"

# ── Download URL ─────────────────────────────────────────────────────────────

DOWNLOAD_BASE="${MOVINGPAPER_APPCAST_DOWNLOAD_BASE:-https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}}"
DOWNLOAD_URL="${DOWNLOAD_BASE}/${DMG_FILENAME}"
step "Download URL: ${DOWNLOAD_URL}"

# ── File size ────────────────────────────────────────────────────────────────

FILE_SIZE=$(stat -f%z "$DMG_PATH")
step "File size: ${FILE_SIZE} bytes"

# ── EdDSA signature ─────────────────────────────────────────────────────────

info "Signing DMG with Sparkle EdDSA"
sign_output="$("$SIGN_TOOL" "$DMG_PATH" 2>&1)"
ed_signature="$(printf '%s\n' "$sign_output" | grep -o 'sparkle:edSignature="[^"]*"' | /usr/bin/sed 's/sparkle:edSignature="\([^"]*\)"/\1/' | head -1)"

if [ -z "$ed_signature" ]; then
    fail "Failed to generate EdDSA signature. Output: $sign_output"
fi
step "EdDSA signature: ${ed_signature:0:40}..."

# ── Publication date ─────────────────────────────────────────────────────────

pub_date="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

# ── Release notes (from git history) ──────────────────────────────────────

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
<p class="footer">Moving Paper ${ver} -- your desktop, alive.</p>
HTML
}

generate_release_notes() {
    local ver="$1"

    # Override: SPARKLE_NOTES_SINCE=v0.008 to diff from a specific tag
    # Override: SPARKLE_NOTES="line1\nline2" to set notes directly
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

    # Find the previous release tag to diff against
    local prev_tag
    if [ -n "${SPARKLE_NOTES_SINCE:-}" ]; then
        prev_tag="$SPARKLE_NOTES_SINCE"
    else
        prev_tag=$(git tag --sort=-v:refname | grep '^v' | head -2 | tail -1)
    fi

    # Get user-facing commit messages since the last tag
    # Filter out internal/developer commits — only keep feat/fix/feature work
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

    # If no user-facing commits, use a friendly default
    if [ -z "$commits" ]; then
        commits="Bug fixes and performance improvements"
    fi

    # Build HTML list items — strip prefixes and capitalize first letter
    local items=""
    while IFS= read -r msg; do
        [ -z "$msg" ] && continue
        # Strip conventional commit prefixes (feat:, fix:, etc.)
        local clean
        clean=$(echo "$msg" | sed 's/^[a-z]*: *//')
        # Capitalize first letter using awk (portable across macOS/Linux)
        clean=$(echo "$clean" | awk '{$1=toupper(substr($1,1,1)) substr($1,2)} 1')
        items="${items}    <li>${clean}</li>\n"
    done <<< "$commits"

    release_notes_html "$ver" "$items"
}

# ── Generate appcast XML ────────────────────────────────────────────────────

cat > "$OUTPUT" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Moving Paper Updates</title>
        <description>Moving Paper update feed.</description>
        <language>en</language>
        <item>
            <title>Moving Paper ${VERSION}</title>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_MACOS}</sparkle:minimumSystemVersion>
            <pubDate>${pub_date}</pubDate>
            <description><![CDATA[
$(generate_release_notes "$VERSION")
            ]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${FILE_SIZE}"
                type="application/x-apple-diskimage"
                sparkle:edSignature="${ed_signature}" />
        </item>
    </channel>
</rss>
APPCAST

# Validate XML
if command -v xmllint &>/dev/null; then
    xmllint --noout "$OUTPUT" 2>&1 && step "XML validated"
fi

info "Appcast generated: ${OUTPUT}"
