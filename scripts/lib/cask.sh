#!/usr/bin/env bash
#
# cask.sh — Pin the Homebrew Cask to the DMG a release just built, so the Cask
# never trails a release. Sourced by the release script; needs `fail` and `step`.

# bump_cask <cask-file> <version> <sha256-file>
# Rewrites the `version` and `sha256` lines and proves both changed. Fails
# closed on a missing file, a malformed checksum or a line it could not find.
bump_cask() {
    local cask="$1" version="$2" sha_file="$3" sha
    [ -f "$cask" ] || fail "Cask not found at ${cask}"
    [ -f "$sha_file" ] || fail "Checksum file not found at ${sha_file}"
    sha="$(awk 'NR == 1 { print $1 }' "$sha_file")"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "Cask bump needs a SHA-256 in ${sha_file}, got '${sha}'"
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Cask bump needs a numeric version, got '${version}'"

    /usr/bin/sed -i '' -E \
        -e "s/^(  version )\"[^\"]+\"\$/\\1\"${version}\"/" \
        -e "s/^(  sha256 )\"[0-9a-f]{64}\"\$/\\1\"${sha}\"/" \
        "$cask"

    grep -q "^  version \"${version}\"\$" "$cask" || fail "The version line was not updated in ${cask}"
    grep -q "^  sha256 \"${sha}\"\$" "$cask" || fail "The sha256 line was not updated in ${cask}"
    step "Pinned ${cask} to v${version}"
}
