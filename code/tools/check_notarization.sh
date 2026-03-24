#!/bin/bash
# meta: updated=2026-03-15 06:58 checked=-
# Check notarization status and staple if accepted.
# Usage: check_notarization.sh <submission-id>
# Intended to be run via cron or launchd.

set -euo pipefail

remove_cron_job() {
    local new_crontab
    new_crontab=$(crontab -l 2>/dev/null | grep -v "check_notarization.sh" || true)
    if [ -n "$new_crontab" ]; then
        echo "$new_crontab" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
    echo "==> Cron job removed."
}

ID="${1:?Usage: check_notarization.sh <submission-id>}"
PROFILE="notarytool-profile"
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$PROJECT_DIR/build/export/ClaudeUsageTracker.app"
ZIP="$PROJECT_DIR/build/ClaudeUsageTracker.zip"
LOG="$PROJECT_DIR/build/notarization.log"

STATUS=$(xcrun notarytool info "$ID" --keychain-profile "$PROFILE" 2>&1 | grep 'status:' | awk '{print $2}')

echo "$(date '+%Y-%m-%d %H:%M:%S') status=$STATUS" >> "$LOG"

case "$STATUS" in
  Accepted)
    echo "==> Notarization accepted! Stapling..."
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl --assess --type execute "$APP" 2>&1 | tee -a "$LOG"
    echo "==> Done. Signed zip ready at $ZIP"

    # Remove cron job
    remove_cron_job

    # Notify
    osascript -e 'display notification "Notarization accepted. Ready to publish." with title "ClaudeUsageTracker"'
    ;;
  Invalid)
    echo "==> Notarization FAILED."
    xcrun notarytool log "$ID" --keychain-profile "$PROFILE" 2>&1 | tee -a "$LOG"
    remove_cron_job
    osascript -e 'display notification "Notarization FAILED. Check log." with title "ClaudeUsageTracker"'
    ;;
  *)
    echo "Still in progress."
    ;;
esac
