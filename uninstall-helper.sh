#!/bin/sh
# Removes the root fan-control daemon that the app installs. Run with sudo.
set -eu
label=local.minitherm.helper
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
launchctl bootout system/$label 2>/dev/null || true
rm -f "/Library/PrivilegedHelperTools/$label" "/Library/LaunchDaemons/$label.plist"
echo "removed $label"
