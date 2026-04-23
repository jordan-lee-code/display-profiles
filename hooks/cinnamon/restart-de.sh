#!/bin/bash
# Restart the Cinnamon compositor and re-assert the xrandr profile afterwards.
#
# Usage: restart-de.sh [profile-dir]
#
# cinnamon --replace must be run in the background and disowned so this
# script can exit cleanly. nohup prevents SIGHUP from killing the new
# compositor process when the parent shell exits.
#
# Cinnamon reads cinnamon-monitors.xml on startup and auto-enables any
# connected output that is not listed in a saved configuration. If a
# profile-dir is provided and contains an xrandr.sh, a background watcher
# polls for the layout change and immediately re-applies xrandr to cancel
# the unwanted re-enable before the user notices.

PROFILE_DIR="${1:-}"

nohup cinnamon --replace >/dev/null 2>&1 &
disown

if [[ -n "$PROFILE_DIR" && -f "$PROFILE_DIR/xrandr.sh" ]]; then
    XRANDR_SCRIPT="$PROFILE_DIR/xrandr.sh"
    (
        # Capture the desired active-monitor count right after xrandr ran.
        before=$(xrandr 2>/dev/null | grep -cE " connected [0-9]+x[0-9]+\+" || echo 0)
        deadline=$((SECONDS + 15))
        while (( SECONDS < deadline )); do
            sleep 0.5
            after=$(xrandr 2>/dev/null | grep -cE " connected [0-9]+x[0-9]+\+" || echo 0)
            if [[ "$after" != "$before" ]]; then
                # Cinnamon changed the layout — re-assert the profile config.
                sleep 0.3
                bash "$XRANDR_SCRIPT" >/dev/null 2>&1
                break
            fi
        done
    ) &
    disown
fi
