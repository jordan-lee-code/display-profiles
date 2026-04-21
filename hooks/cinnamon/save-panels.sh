#!/bin/bash
# Save current Cinnamon panel layout into a profile directory
# Usage: save-panels.sh <profile-dir>

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
