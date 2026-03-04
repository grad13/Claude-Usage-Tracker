#!/bin/bash
# Version extraction utilities

# Get CFBundleShortVersionString from an .app bundle's Info.plist.
# Returns "unknown" if Info.plist is missing or unreadable.
# Usage: get_app_version "/Applications/MyApp.app"
get_app_version() {
    local app_dir="$1"
    local plist="$app_dir/Contents/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$plist" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}
