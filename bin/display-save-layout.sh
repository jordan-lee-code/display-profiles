#!/bin/bash
# Save the current DE panel layout for a named profile
# Usage: display-save-layout.sh <profile>

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
    echo "Usage: display-save-layout.sh <profile>" >&2
    echo "Available profiles:" >&2
    list_profiles | sed 's/^/  /' >&2
    exit 1
fi

PROFILE_DIR="$(get_profiles_dir)/$PROFILE"
if [[ ! -d "$PROFILE_DIR" ]]; then
    echo "Profile '$PROFILE' not found. Create it first with display-new-profile.sh" >&2
    exit 1
fi

DE=$(detect_de)
SAVE_HOOK="$(get_hooks_dir)/$DE/save-panels.sh"

if [[ ! -f "$SAVE_HOOK" ]]; then
    echo "No panel layout hook found for DE: $DE" >&2
    echo "Supported DEs: $(ls "$(get_hooks_dir)")" >&2
    exit 1
fi

bash "$SAVE_HOOK" "$PROFILE_DIR"
echo "Saved $DE panel layout for profile '$PROFILE'"
