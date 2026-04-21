#!/bin/bash
# Apply the saved display mode on startup

MODE=$(cat "$HOME/.config/display-mode" 2>/dev/null || echo "personal")

if [ "$MODE" = "work" ]; then
    "$HOME/bin/display-work.sh"
else
    "$HOME/bin/display-personal.sh"
fi
