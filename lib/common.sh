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

# Debug log written only when errors occur.
get_log_file()    { echo "$HOME/.config/display-profiles/debug.log"; }

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

# Exits with a clear error if a required external command is missing.
require_cmd() {
    local cmd="$1" hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' not found.${hint:+ $hint}" >&2
        exit 1
    fi
}

# Prompts for a 1-based index in [1..max] and stores it in the named variable.
# Keeps re-prompting until the input is a valid number; defaults to 1.
pick_index() {
    local -n _pick_result="$1"
    local max="$2" prompt="$3" input
    while true; do
        read -rp "$prompt" input
        input="${input:-1}"
        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= max )); then
            _pick_result="$input"
            return 0
        fi
        echo "  Invalid: enter a number 1–$max." >&2
    done
}

# Returns one profile name per line, sorted alphabetically.
# Outputs nothing (not an error) if the profiles directory doesn't exist yet.
list_profiles() {
    local dir
    dir="$(get_profiles_dir)"
    [[ -d "$dir" ]] || return 0
    find "$dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
}

# Appends a timestamped error message to the debug log.
log_error() {
    local msg="$1"
    local log_file
    log_file="$(get_log_file)"
    mkdir -p "$(dirname "$log_file")"
    printf '[%s] ERROR: %s\n' "$(date -Iseconds)" "$msg" >> "$log_file"
}
