#!/usr/bin/env bash

set -euo pipefail

APP_NAME="MovingPaper"
BUNDLE_ID="com.8bittts.movingpaper"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_PRODUCTION=false

for arg in "$@"; do
    case "$arg" in
        --production) REQUIRE_PRODUCTION=true ;;
        *) echo "usage: $0 [--production]" >&2; exit 2 ;;
    esac
done

cd "$REPO_ROOT"

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
step() { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$1"; }

require_file() {
    [ -f "$1" ] || fail "Missing required file: $1"
}

require_dir() {
    [ -d "$1" ] || fail "Missing required directory: $1"
}

require_executable() {
    [ -x "$1" ] || fail "Missing executable: $1"
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

assert_plist_value() {
    local plist="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(plist_value "$plist" "$key")"
    [ "$actual" = "$expected" ] || fail "${plist} ${key}: expected '${expected}', got '${actual}'"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    grep -Fq -- "$needle" "$haystack" || fail "${haystack} does not contain ${needle}"
}

verify_app_bundle_shape() {
    local app="$1"
    local plist="${app}/Contents/Info.plist"
    local binary="${app}/Contents/MacOS/${APP_NAME}"

    require_dir "$app"
    require_file "$plist"
    require_executable "$binary"
    require_dir "${app}/Contents/Frameworks/Sparkle.framework"
    require_file "${app}/Contents/Resources/${APP_NAME}.icns"

    assert_plist_value "$plist" "CFBundleIdentifier" "$BUNDLE_ID"
    assert_plist_value "$plist" "CFBundleExecutable" "$APP_NAME"
    assert_plist_value "$plist" "CFBundlePackageType" "APPL"
    assert_plist_value "$plist" "NSPrincipalClass" "NSApplication"
    assert_plist_value "$plist" "SURequireSignedFeed" "true"
    assert_plist_value "$plist" "SUVerifyUpdateBeforeExtraction" "true"

    otool -L "$binary" | grep -q "@rpath/Sparkle.framework" || fail "${binary} is not linked to bundled Sparkle via @rpath"
}

verify_release_artifacts() {
    local version="$1"
    local build_number="$2"
    local app="build/${APP_NAME}.app"
    local plist="${app}/Contents/Info.plist"
    local dmg="build/${APP_NAME}-${version}.dmg"
    local sha_file="build/${APP_NAME}-${version}.sha256"
    local appcast="build/appcast.xml"

    verify_app_bundle_shape "$app"
    assert_plist_value "$plist" "CFBundleShortVersionString" "$version"
    assert_plist_value "$plist" "CFBundleVersion" "$build_number"
    require_file "$dmg"
    require_file "$sha_file"
    require_file "$appcast"

    codesign --verify --strict --deep --verbose=2 "$app" >/dev/null
    step "Release app signature verified"

    local entitlements
    entitlements="$(codesign -dvvv --entitlements :- "$app" 2>&1)"
    grep -q "<key>com.apple.security.app-sandbox</key>" <<< "$entitlements" || fail "Release app entitlements missing app sandbox key"
    grep -q "<false/>" <<< "$entitlements" || fail "Release app sandbox entitlement should be false"

    if spctl -a -vv "$app" >/dev/null 2>&1; then
        step "Release app accepted by Gatekeeper"
    else
        [ "$REQUIRE_PRODUCTION" = false ] || fail "Release app rejected by Gatekeeper"
        warn "Release app was not accepted by Gatekeeper"
    fi

    codesign -dvvv "$dmg" >/dev/null 2>&1 || fail "DMG is not signed"
    if spctl -a -vv -t open --context context:primary-signature "$dmg" >/dev/null 2>&1; then
        step "DMG accepted by Gatekeeper"
    else
        [ "$REQUIRE_PRODUCTION" = false ] || fail "DMG rejected by Gatekeeper"
        warn "DMG was not accepted by Gatekeeper"
    fi

    if xcrun stapler validate "$dmg" >/dev/null 2>&1; then
        step "DMG notarization ticket verified"
    else
        [ "$REQUIRE_PRODUCTION" = false ] || fail "DMG notarization ticket missing or invalid"
        warn "DMG notarization ticket missing or invalid"
    fi

    local expected actual
    expected="$(awk '{print $1}' "$sha_file")"
    actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || fail "DMG checksum mismatch"
    step "DMG checksum verified"

    local dmg_bytes
    dmg_bytes="$(stat -f%z "$dmg")"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$appcast"
    fi
    assert_contains "$appcast" "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>"
    assert_contains "$appcast" "<sparkle:version>${build_number}</sparkle:version>"
    assert_contains "$appcast" "MovingPaper-${version}.dmg"
    assert_contains "$appcast" "length=\"${dmg_bytes}\""
    assert_contains "$appcast" "sparkle-signatures:"
    assert_contains "$appcast" "sparkle:edSignature="
    tools/sparkle/bin/sign_update --verify "$appcast" >/dev/null 2>&1 || fail "Sparkle appcast signature verification failed"
    step "Signed appcast metadata verified"
}

info "Checking repository smoke-test inputs"
require_file "Package.swift"
require_file "sources/Resources/Info.plist"
require_file "MovingPaper.entitlements"
require_file "scripts/build_and_run.sh"
require_file "scripts/build-dmg.sh"
require_executable "tools/sparkle/bin/sign_update"
require_file "build/movingpaper.png"
require_file "build/yen.png"
require_file "build/tests/test-00.gif"
require_file "build/tests/test-01.mp4"

if grep -q 'for item in "$BUILD_DIR"/\*' scripts/build-dmg.sh; then
    fail "build-dmg.sh contains broad build/ cleanup that can delete tracked sample assets"
fi
step "Tracked build assets are protected from broad cleanup"

grep -q 'scripts/smoke-test.sh" --production' scripts/release-movingpaper.sh \
    || fail "release-movingpaper.sh must run production smoke before publishing"
grep -q "expected_dmg_bytes" scripts/release-movingpaper.sh \
    || fail "release-movingpaper.sh must verify live appcast artifact length"
step "Release workflow enforces production smoke and live appcast metadata checks"

if [ -f ".codex/environments/environment.toml" ]; then
    run_command="$(awk -F' = ' '$1 == "command" { gsub(/"/, "", $2); print $2 }' .codex/environments/environment.toml)"
    [ -z "$run_command" ] || [ -x "$run_command" ] || fail "Codex Run action points at a missing executable: $run_command"
    step "Codex Run action target exists"
fi

info "Running automated tests"
swift test

info "Building release binary"
swift build -c release

info "Assembling non-launching local app bundle"
./scripts/build_and_run.sh --build-only >/dev/null
verify_app_bundle_shape "build/local-run/${APP_NAME}.app"
step "Local staged app bundle verified"

version="$(plist_value sources/Resources/Info.plist CFBundleShortVersionString)"
build_number="$(plist_value sources/Resources/Info.plist CFBundleVersion)"
if [ -d "build/${APP_NAME}.app" ] || [ "$REQUIRE_PRODUCTION" = true ]; then
    info "Verifying production release artifacts for v${version}"
    verify_release_artifacts "$version" "$build_number"
else
    warn "Skipping production artifact verification because build/${APP_NAME}.app is absent"
fi

info "Smoke test complete"
