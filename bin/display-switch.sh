#!/bin/bash
# Apply a named display profile
# Usage: display-switch.sh <profile>

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

echo "$PROFILE" > "$HOME/.config/display-mode"
echo "Done."
