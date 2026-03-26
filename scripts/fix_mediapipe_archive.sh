#!/bin/sh
set -e

ensure_plist_dict() {
    plist="$1"
    if [ ! -f "$plist" ]; then
        cat > "$plist" <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLISTEOF
    fi
}

set_plist_value() {
    plist="$1"
    key="$2"
    type="$3"
    value="$4"
    /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "$plist" 2>/dev/null || true
}

reset_supported_platforms() {
    plist="$1"
    /usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string iPhoneOS" "$plist" 2>/dev/null || true
}

patch_framework_from_binary() {
    framework_binary="$1"
    framework_name="$2"

    if [ -z "$framework_binary" ] || [ ! -e "$framework_binary" ]; then
        exit 0
    fi

    framework_dir="$(dirname "$framework_binary")"
    plist="$framework_dir/Info.plist"

    ensure_plist_dict "$plist"
    set_plist_value "$plist" MinimumOSVersion string "${IPHONEOS_DEPLOYMENT_TARGET}"
    set_plist_value "$plist" CFBundleShortVersionString string "${MARKETING_VERSION}"
    set_plist_value "$plist" CFBundleVersion string "${CURRENT_PROJECT_VERSION}"
    set_plist_value "$plist" CFBundleName string "${framework_name}"
    set_plist_value "$plist" CFBundleExecutable string "${framework_name}"
    set_plist_value "$plist" CFBundleIdentifier string "com.pushx.vendor.${framework_name}"
    set_plist_value "$plist" CFBundleInfoDictionaryVersion string "6.0"
    set_plist_value "$plist" CFBundlePackageType string "FMWK"
    reset_supported_platforms "$plist"
    echo "Patched: $plist"

    # Vendor XCFrameworks often lack dSYMs; App Store symbol upload then errors on missing
    # UUIDs. Prefer extracting a dSYM with dsymutil when DWARF is still in the Mach-O;
    # otherwise strip debug symbols so the uploader does not expect a dSYM we cannot ship.
    dsym_ok=0
    if [ -n "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
        mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
        dsym_bundle="${DWARF_DSYM_FOLDER_PATH}/${framework_name}.framework.dSYM"
        rm -rf "$dsym_bundle"
        if xcrun dsymutil "$framework_binary" -o "$dsym_bundle" >/dev/null 2>&1 \
            && [ -d "$dsym_bundle" ]; then
            echo "Generated dSYM: $dsym_bundle"
            dsym_ok=1
        fi
    fi

    # Info.plist CFBundleIdentifier must match the sealed codesign identifier. Google's
    # prebuilt binaries keep their original identifiers until we re-sign.
    identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
    bundle_id="com.pushx.vendor.${framework_name}"
    if [ -n "$identity" ] && [ "$identity" != "-" ] && [ "$identity" != "" ]; then
        rm -rf "$framework_dir/_CodeSignature"
        if [ "$dsym_ok" -eq 0 ]; then
            echo "note: no DWARF for ${framework_name}; strip -S before re-sign (avoids missing dSYM upload errors)"
            /usr/bin/strip -S "$framework_binary" || true
        fi
        /usr/bin/codesign --force --sign "$identity" --identifier "$bundle_id" "$framework_binary" || exit 1
        /usr/bin/codesign --force --sign "$identity" "$framework_dir" || exit 1
        echo "Re-signed: $framework_dir as $bundle_id"
    else
        echo "warning: no code signing identity; skipped resign for $framework_name (archive may fail validation)"
    fi
}

patch_framework_from_binary "${SCRIPT_INPUT_FILE_1:-}" "MediaPipeTasksVision"
patch_framework_from_binary "${SCRIPT_INPUT_FILE_2:-}" "MediaPipeCommonGraphLibraries"
