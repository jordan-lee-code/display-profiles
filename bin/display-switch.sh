#!/bin/bash
# Apply a named display profile.
# Usage: display-switch.sh <profile>
#
# Applies the xrandr config, then restores the panel layout and restarts the
# DE compositor if a panel-layout.sh exists for the profile. The compositor
# restart is skipped when there is no panel layout because xrandr alone does
# not require it, and an unnecessary restart is disruptive.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
    echo "Usage: display-switch.sh <profile>" >&2
    echo "Available profiles:" >&2
    list_profiles | sed 's/^/  /' >&2
    exit 1
fi

PROFILE_DIR="$(get_profiles_dir)/$PROFILE"
if [[ ! -d "$PROFILE_DIR" ]]; then
    echo "Profile '$PROFILE' not found in $(get_profiles_dir)" >&2
    exit 1
fi

echo "Applying profile: $PROFILE"

bash "$PROFILE_DIR/xrandr.sh"

if [[ -f "$PROFILE_DIR/panel-layout.sh" ]]; then
    echo "  Restoring panel layout..."
    bash "$PROFILE_DIR/panel-layout.sh"

    DE=$(detect_de)
    RESTART_HOOK="$(get_hooks_dir)/$DE/restart-de.sh"
    if [[ -f "$RESTART_HOOK" ]]; then
        echo "  Restarting $DE..."
        bash "$RESTART_HOOK"
    fi
fi

# Write the active profile name so display-apply-saved.sh can restore it on
# the next login, and so display-shutdown.sh knows the current state.
echo "$PROFILE" > "$HOME/.config/display-mode"
echo "Done."
