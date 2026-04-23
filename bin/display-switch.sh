#!/bin/bash
set -euo pipefail
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

require_cmd xrandr "Install with: sudo apt install x11-xserver-utils"

echo "Applying profile: $PROFILE"

if [[ ! -f "$PROFILE_DIR/xrandr.sh" ]]; then
    echo "Profile '$PROFILE' is missing xrandr.sh — recreate it with display-new-profile.sh" >&2
    exit 1
fi
if ! bash "$PROFILE_DIR/xrandr.sh"; then
    log_error "xrandr failed for profile '$PROFILE'"
    echo "xrandr failed for profile '$PROFILE'. See $(get_log_file) for details." >&2
    exit 1
fi

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

# Write the active profile name so display-apply-saved.sh can restore it on login.
echo "$PROFILE" > "$HOME/.config/display-mode"
echo "Done."
