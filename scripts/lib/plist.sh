# Shared PlistBuddy helpers for MovingPaper packaging scripts.
# Source from a script after REPO_ROOT is set:
#   # shellcheck source=lib/plist.sh
#   source "${REPO_ROOT}/scripts/lib/plist.sh"

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

apply_sparkle_plist_keys() {
    local plist="$1"
    local feed_url="$2"
    local public_ed_key="$3"

    plist_set "$plist" "SUEnableAutomaticChecks" bool true
    plist_set "$plist" "SUFeedURL" string "$feed_url"
    plist_set "$plist" "SUPublicEDKey" string "$public_ed_key"
    plist_set "$plist" "SUScheduledCheckInterval" integer 3600
    plist_set "$plist" "SUVerifyUpdateBeforeExtraction" bool true
    plist_set "$plist" "SURequireSignedFeed" bool true
}
