#!/bin/bash
# Save Cinnamon's monitor layout file into a profile directory.
# Usage: save-monitors.sh <profile-dir>
#
# Copies ~/.config/cinnamon-monitors.xml into the profile directory so that
# display-switch.sh can restore it before restarting Cinnamon. Without this,
# Cinnamon reads the stale monitors.xml on restart and re-enables outputs that
# the xrandr profile has turned off.

PROFILE_DIR="${1:-}"
[[ -z "$PROFILE_DIR" ]] && { echo "Usage: save-monitors.sh <profile-dir>" >&2; exit 1; }

SRC="$HOME/.config/cinnamon-monitors.xml"
if [[ ! -f "$SRC" ]]; then
    echo "No cinnamon-monitors.xml found at $SRC — skipping." >&2
    exit 0
fi

cp "$SRC" "$PROFILE_DIR/cinnamon-monitors.xml"
