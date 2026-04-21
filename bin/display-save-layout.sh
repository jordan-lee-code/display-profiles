#!/bin/bash
# Save the current Cinnamon panel layout for the given mode
# Usage: display-save-layout.sh work|personal

MODE="${1:-}"
if [[ "$MODE" != "work" && "$MODE" != "personal" ]]; then
    echo "Usage: display-save-layout.sh work|personal" >&2
    exit 1
fi

SAVE_FILE="$HOME/.config/cinnamon-panels-${MODE}.sh"

echo "#!/bin/bash" > "$SAVE_FILE"
for key in panels-enabled panels-height panels-autohide panels-hide-delay panels-show-delay enabled-applets next-applet-id; do
    val=$(dconf read /org/cinnamon/$key)
    [[ -n "$val" ]] && echo "dconf write /org/cinnamon/$key '$val'" >> "$SAVE_FILE"
done
chmod +x "$SAVE_FILE"

echo "Saved $MODE panel layout to $SAVE_FILE"
