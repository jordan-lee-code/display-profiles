#!/bin/bash
# Prompt for display mode, save the choice, then power off

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

zenity --question \
    --title="Shutdown — Display Mode" \
    --text="Select display mode for next startup:" \
    --ok-label="Work (DP-2 only)" \
    --cancel-label="Personal (both screens)" \
    2>/dev/null

if [ $? -eq 0 ]; then
    echo "work" > "$HOME/.config/display-mode"
else
    echo "personal" > "$HOME/.config/display-mode"
fi

systemctl poweroff
