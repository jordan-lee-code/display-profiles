#!/bin/bash
# Apply the last saved profile on login (called by autostart)

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

PROFILE=$(cat "$HOME/.config/display-mode" 2>/dev/null)
[[ -z "$PROFILE" ]] && exit 0

exec "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/display-switch.sh" "$PROFILE"
