#!/bin/bash
# Apply the last saved display profile on login.
# Called by the autostart desktop entry on every session start.
#
# Silently exits if no profile has been saved yet — this is normal on first
# boot before any profile has been selected at shutdown.
#
# Uses exec to replace this process with display-switch.sh so the PID in
# the autostart entry maps directly to the switching script, not a wrapper.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

PROFILE=$(cat "$HOME/.config/display-mode" 2>/dev/null)
[[ -z "$PROFILE" ]] && exit 0

exec "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/display-switch.sh" "$PROFILE"
