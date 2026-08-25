#!/bin/bash
set -euo pipefail
# Apply a named display profile.
# Usage: display-switch.sh [--no-persist] <profile>
#
# Applies the xrandr config, then restores the panel layout and restarts the
# DE compositor if a panel-layout.sh exists for the profile. The compositor
# restart is skipped when there is no panel layout because xrandr alone does
# not require it, and an unnecessary restart is disruptive.
#
# --no-persist applies the profile without recording it as the profile to
# restore at next login. display-switch-client.sh uses it for the temporary
# layouts it builds from a streaming client's request.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

PERSIST=1
declare -a POSITIONAL=()
while (( $# )); do
    case "$1" in
        --no-persist) PERSIST=0; shift ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
    echo "Usage: display-switch.sh [--no-persist] <profile>" >&2
    echo "Available profiles:" >&2
    list_profiles | sed 's/^/  /' >&2
    exit 1
fi

PROFILE_DIR="$(get_profiles_dir)/$PROFILE"
if [[ ! -d "$PROFILE_DIR" ]]; then
    echo "Profile '$PROFILE' not found in $(get_profiles_dir)" >&2
    exit 1
fi

require_cmd xrandr "Install with: sudo apt install x11-xserver-utils"

echo "Applying profile: $PROFILE"

if [[ ! -f "$PROFILE_DIR/xrandr.sh" ]]; then
    echo "Profile '$PROFILE' is missing xrandr.sh — recreate it with display-new-profile.sh" >&2
    exit 1
fi

# Retry rather than give up on the first attempt. A switch requested while the
# outputs are still settling, which is exactly what happens at login, on resume
# and as a stream tears down, can lose a race that the identical command wins a
# second later. xrandr's own stderr is captured into the log because a bare
# "xrandr failed" line tells you nothing when you come back to it days later.
attempt=1
while (( attempt <= 3 )); do
    if err=$(bash "$PROFILE_DIR/xrandr.sh" 2>&1); then
        break
    fi
    log_error "xrandr failed for profile '$PROFILE' (attempt $attempt/3): ${err:-no error output}"
    if (( attempt == 3 )); then
        echo "xrandr failed for profile '$PROFILE'. See $(get_log_file) for details." >&2
        exit 1
    fi
    sleep 1
    (( attempt++ ))
done

if [[ -f "$PROFILE_DIR/panel-layout.sh" ]]; then
    echo "  Restoring panel layout..."
    bash "$PROFILE_DIR/panel-layout.sh"

    DE=$(detect_de)

    # Overwrite the DE's stored monitor layout before restarting so it applies
    # the profile's config rather than re-enabling all connected outputs.
    if [[ -f "$PROFILE_DIR/cinnamon-monitors.xml" ]]; then
        cp "$PROFILE_DIR/cinnamon-monitors.xml" "$HOME/.config/cinnamon-monitors.xml"
    fi

    RESTART_HOOK="$(get_hooks_dir)/$DE/restart-de.sh"
    if [[ -f "$RESTART_HOOK" ]]; then
        echo "  Restarting $DE..."
        bash "$RESTART_HOOK" "$PROFILE_DIR"
    fi
fi

# Write the active profile name so display-apply-saved.sh can restore it on
# login. Skipped for temporary layouts, because a resolution chosen to suit a
# remote client is not one you want to come back to at your own desk.
if (( PERSIST )); then
    echo "$PROFILE" > "$HOME/.config/display-mode"
fi
echo "Done."
