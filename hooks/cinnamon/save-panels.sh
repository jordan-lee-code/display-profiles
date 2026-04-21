#!/bin/bash
# Save the current Cinnamon panel layout into a profile directory.
# Usage: save-panels.sh <profile-dir>
#
# Reads each relevant dconf key and writes a panel-layout.sh restore script
# into the profile directory. display-switch.sh sources that script on every
# profile switch to recreate the exact panel arrangement.
#
# Keys captured:
#   panels-enabled      — which panels exist, which monitor, and their position
#   panels-height       — pixel height per panel
#   panels-autohide     — autohide setting per panel
#   panels-hide-delay   — delay before hiding (ms)
#   panels-show-delay   — delay before showing (ms)
#   enabled-applets     — which applets are loaded and on which panel/zone/slot
#   next-applet-id      — counter used when adding new applets; must match or
#                         new applets added later will collide with saved IDs

PROFILE_DIR="${1:-}"
[[ -z "$PROFILE_DIR" ]] && { echo "Usage: save-panels.sh <profile-dir>" >&2; exit 1; }

SAVE_FILE="$PROFILE_DIR/panel-layout.sh"
echo "#!/bin/bash" > "$SAVE_FILE"

for key in panels-enabled panels-height panels-autohide panels-hide-delay \
           panels-show-delay enabled-applets next-applet-id; do
    val=$(dconf read /org/cinnamon/$key 2>/dev/null)
    [[ -n "$val" ]] && echo "dconf write /org/cinnamon/$key '$val'" >> "$SAVE_FILE"
done

chmod +x "$SAVE_FILE"
