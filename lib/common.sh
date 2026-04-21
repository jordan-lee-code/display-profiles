#!/bin/bash
# Shared functions sourced by all display-profiles scripts.
# Sourcing with BASH_SOURCE means _REPO_DIR resolves correctly whether this
# file is called directly, sourced from a symlink in ~/bin/, or from any
# working directory.

_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

get_repo_dir()    { echo "$_REPO_DIR"; }
get_hooks_dir()   { echo "$_REPO_DIR/hooks"; }

# Profiles live outside the repo so they survive a repo update or reinstall.
get_profiles_dir(){ echo "$HOME/.config/display-profiles"; }

# XDG_CURRENT_DESKTOP is the standard variable set by the session manager.
# DESKTOP_SESSION is a fallback used by older DEs and display managers.
# Both are lowercased before matching so "Cinnamon" and "cinnamon" both work.
detect_de() {
    local desktop="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
    case "${desktop,,}" in
        *cinnamon*)     echo "cinnamon" ;;
        *gnome*)        echo "gnome"    ;;
        *kde*|*plasma*) echo "kde"      ;;
        *xfce*)         echo "xfce"     ;;
        *mate*)         echo "mate"     ;;
        *)              echo "unknown"  ;;
    esac
}

# Returns one profile name per line, sorted alphabetically.
# Outputs nothing (not an error) if the profiles directory doesn't exist yet.
list_profiles() {
    local dir
    dir="$(get_profiles_dir)"
    [[ -d "$dir" ]] || return 0
    find "$dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
}

# Show a profile selection dialog and print the chosen name to stdout.
# Uses a Zenity radiolist when a display is available, falling back to a
# terminal select menu when running without X (e.g. from a bare terminal or
# via SSH). Returns 1 if the user cancels or no profiles exist.
select_profile() {
    local title="${1:-Select display profile}"
    local prompt="${2:-Select display profile for next startup:}"
    mapfile -t profiles < <(list_profiles)

    if [[ ${#profiles[@]} -eq 0 ]]; then
        echo "No profiles found. Run display-new-profile.sh to create one." >&2
        return 1
    fi

    if command -v zenity &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
        # Build the zenity argument list: TRUE/FALSE toggles precede each
        # profile name. The first profile is pre-selected.
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
