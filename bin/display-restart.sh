#!/bin/bash
# Prompt for a display profile, save the choice, then reboot.
#
# DISPLAY and XAUTHORITY are exported explicitly because this script is
# often called from a panel button or menu entry where those variables may
# not be set, which would prevent the Zenity dialog from opening. :0 is the
# correct value for a single-user X session; adjust if your setup differs.

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

# The chosen profile is written to disk before reboot so that
# display-apply-saved.sh can restore it on the next login.
PROFILE=$(select_profile "Restart — Display Profile") || exit 1
echo "$PROFILE" > "$HOME/.config/display-mode"
systemctl reboot
