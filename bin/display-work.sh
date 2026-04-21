#!/bin/bash
# Work mode: DP-2 (right) only — DP-0 disabled

set -euo pipefail

echo "Applying WORK display mode (DP-2 only)..."

xrandr \
    --output DP-0 --off \
    --output DP-2 --mode 2560x1440 --rate 165.08 --primary

echo "  DP-0: OFF"
echo "  DP-2: 2560x1440@165.08Hz [PRIMARY]"

if [ -f "$HOME/.config/cinnamon-panels-work.sh" ]; then
    echo "Restoring work panel layout..."
    bash "$HOME/.config/cinnamon-panels-work.sh"
    nohup cinnamon --replace >/dev/null 2>&1 &
    disown
else
    echo "  (no work panel layout saved — run: display-save-layout.sh work)"
fi

echo "Done."
