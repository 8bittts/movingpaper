#!/usr/bin/env bash
#
# Shared app-icon step for the scripts that stage MovingPaper.app.
# Requires scripts/lib/plist.sh to be sourced first (plist_set).

# Compile the Icon Composer document into a staged bundle.
#   compile_app_icon <icon-document> <resources-dir> <info-plist> <icon-name>
# actool writes Assets.car, which carries the layered Liquid Glass icon and its
# appearance variants, and a flattened <icon-name>.icns. The Info.plist gets the
# two keys that point at them. Fails when any input or output is missing.
compile_app_icon() {
    local icon_document="$1"
    local resources_dir="$2"
    local info_plist="$3"
    local icon_name="$4"

    [ -f "${icon_document}/icon.json" ] || { echo "Missing icon document at ${icon_document}" >&2; return 1; }
    [ -f "$info_plist" ] || { echo "Missing Info.plist at ${info_plist}" >&2; return 1; }

    # actool resolves relative paths against its own working directory, not ours.
    icon_document="$(cd "$icon_document" && pwd)" || return 1
    resources_dir="$(cd "$resources_dir" && pwd)" || return 1

    local deployment_target
    deployment_target="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$info_plist")" || return 1

    local partial_plist actool_output
    partial_plist="$(mktemp "${TMPDIR:-/tmp}/movingpaper-icon.XXXXXX")" || return 1
    if ! actool_output="$(xcrun actool "$icon_document" \
        --compile "$resources_dir" \
        --app-icon "$icon_name" \
        --platform macosx \
        --minimum-deployment-target "$deployment_target" \
        --output-partial-info-plist "$partial_plist" \
        --output-format human-readable-text 2>&1)"; then
        /bin/rm -f "$partial_plist"
        echo "actool failed to compile ${icon_document}:" >&2
        echo "$actool_output" >&2
        return 1
    fi
    /bin/rm -f "$partial_plist"

    [ -s "${resources_dir}/Assets.car" ] || { echo "actool wrote no Assets.car into ${resources_dir}" >&2; return 1; }
    [ -s "${resources_dir}/${icon_name}.icns" ] || { echo "actool wrote no ${icon_name}.icns into ${resources_dir}" >&2; return 1; }

    plist_set "$info_plist" "CFBundleIconFile" string "$icon_name"
    plist_set "$info_plist" "CFBundleIconName" string "$icon_name"
}
