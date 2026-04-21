#!/bin/bash
# Shared functions — sourced by all display-profiles scripts

_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

get_repo_dir()    { echo "$_REPO_DIR"; }
get_hooks_dir()   { echo "$_REPO_DIR/hooks"; }
get_profiles_dir(){ echo "$HOME/.config/display-profiles"; }

detect_de() {
    local desktop="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
    case "${desktop,,}" in
        *cinnamon*) echo "cinnamon" ;;
        *gnome*)    echo "gnome"    ;;
        *kde*|*plasma*) echo "kde"  ;;
        *xfce*)     echo "xfce"     ;;
        *mate*)     echo "mate"     ;;
        *)          echo "unknown"  ;;
    esac
}

list_profiles() {
    local dir
    dir="$(get_profiles_dir)"
    [[ -d "$dir" ]] || return 0
    find "$dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
}

# Print a profile selection dialog.
# Writes chosen profile name to stdout. Returns 1 if cancelled.
select_profile() {
    local title="${1:-Select display profile}"
    local prompt="${2:-Select display profile for next startup:}"
    mapfile -t profiles < <(list_profiles)

    if [[ ${#profiles[@]} -eq 0 ]]; then
        echo "No profiles found. Run display-new-profile.sh to create one." >&2
        return 1
    fi

    if command -v zenity &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
        local zenity_args=()
        local first=true
        for p in "${profiles[@]}"; do
            $first && zenity_args+=(TRUE) || zenity_args+=(FALSE)
            zenity_args+=("$p")
            first=false
        done
        zenity --list \
            --title="$title" \
            --text="$prompt" \
            --radiolist \
            --column="" --column="Profile" \
            "${zenity_args[@]}" 2>/dev/null || return 1
    else
        echo "$prompt" >&2
        select p in "${profiles[@]}"; do
            [[ -n "$p" ]] && { echo "$p"; return 0; }
        done
        return 1
    fi
}
