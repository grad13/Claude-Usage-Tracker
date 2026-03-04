#!/bin/bash
# LaunchServices utilities: shared by build-and-install.sh and rollback.sh

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

# Deregister stale app copies from DerivedData and Trash.
# Requires: APP_NAME, DERIVED_DATA (set by caller)
deregister_stale_apps() {
    for dd in "$DERIVED_DATA"/${APP_NAME}-*/Build/Products/*/${APP_NAME}.app; do
        [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
    done
    for trash in "$HOME/.Trash/${APP_NAME}"*.app; do
        [ -d "$trash" ] && "$LSREGISTER" -u "$trash" 2>/dev/null || true
    done
}
