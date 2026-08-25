#!/bin/bash
# Restart the Cinnamon compositor and re-assert the xrandr profile afterwards.
#
# Usage: restart-de.sh [profile-dir]
#
# cinnamon --replace must be run in the background and disowned so this
# script can exit cleanly. nohup prevents SIGHUP from killing the new
# compositor process when the parent shell exits.
#
# Cinnamon reads cinnamon-monitors.xml on startup and then reconfigures the
# outputs itself, which does not reliably reproduce what the profile asked
# for. If a profile-dir is provided and contains an xrandr.sh, a background
# watcher polls for that drift and re-applies xrandr to correct it.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../lib/common.sh"

PROFILE_DIR="${1:-}"

nohup cinnamon --replace >/dev/null 2>&1 &
disown

if [[ -n "$PROFILE_DIR" && -f "$PROFILE_DIR/xrandr.sh" ]]; then
    XRANDR_SCRIPT="$PROFILE_DIR/xrandr.sh"
    (
        # Captured immediately after xrandr.sh succeeded, so this is the state
        # the profile actually asked for, refresh rates included.
        WANT="$(output_signature)"

        # Cinnamon can settle and then reconfigure again a moment later, so the
        # watcher keeps correcting for the whole window rather than stopping at
        # the first fix. The cap is there so a profile that genuinely cannot be
        # applied does not turn into a re-apply loop.
        deadline=$((SECONDS + 20))
        fixes=0
        while (( SECONDS < deadline )); do
            sleep 0.5
            [[ "$(output_signature)" == "$WANT" ]] && continue
            sleep 0.3
            bash "$XRANDR_SCRIPT" >/dev/null 2>&1
            (( ++fixes >= 3 )) && break
            sleep 1
        done
    ) &
    disown
fi
