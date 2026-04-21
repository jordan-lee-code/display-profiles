#!/bin/bash
# Prompt for display profile, save the choice, then reboot

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

PROFILE=$(select_profile "Restart — Display Profile") || exit 1
echo "$PROFILE" > "$HOME/.config/display-mode"
systemctl reboot
