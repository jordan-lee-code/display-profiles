#!/bin/bash
# Personal mode: DP-0 (left) is primary, DP-2 (right) is secondary — both at 165.08Hz

set -euo pipefail

echo "Applying PERSONAL display mode (DP-0 primary)..."

xrandr \
    --output DP-0 --mode 2560x1440 --rate 165.08 --primary \
    --output DP-2 --mode 2560x1440 --rate 165.08 --right-of DP-0

echo "  DP-0: 2560x1440@165.08Hz [left, PRIMARY]"
echo "  DP-2: 2560x1440@165.08Hz [right]"

if [ -f "$HOME/.config/cinnamon-panels-personal.sh" ]; then
    echo "Restoring personal panel layout..."
    bash "$HOME/.config/cinnamon-panels-personal.sh"
    nohup cinnamon --replace >/dev/null 2>&1 &
    disown
else
    echo "  (no personal panel layout saved — run: display-save-layout.sh personal)"
fi

echo "Done."
