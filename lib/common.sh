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

# --- Mode discovery -------------------------------------------------------
# These read xrandr rather than any saved profile, so they describe what the
# hardware can actually do right now. display-switch-client.sh uses them to
# match the host to whatever a streaming client asked for.

# Prints "WIDTHxHEIGHT RATE" for every mode of a connected output, one line
# per rate, in the order xrandr lists them. Rates keep the two-decimal string
# form xrandr prints because --rate is matched against that exact text.
list_output_modes() {
    local output="$1"
    xrandr | awk -v out="$output" '
        $0 ~ "^"out" connected" { found=1; next }
        found && /^[A-Z]/ { exit }
        found && /^[[:space:]]+[0-9]+x[0-9]+/ {
            match($0, /[0-9]+x[0-9]+/)
            res = substr($0, RSTART, RLENGTH)
            for (i = 2; i <= NF; i++) {
                r = $i; gsub(/[*+]/, "", r)
                if (r ~ /^[0-9]+\.[0-9]+$/) print res, r
            }
        }
    '
}

# Prints an output's preferred resolution as WIDTHxHEIGHT. xrandr marks the
# panel's preferred mode with '+', which is the one to drive the panel at;
# the first listed mode is used as a fallback if no mode carries the marker.
# Prints nothing if the output is not connected.
output_preferred_res() {
    local output="$1"
    xrandr | awk -v out="$output" '
        $0 ~ "^"out" connected" { found=1; next }
        found && /^[A-Z]/ { exit }
        found && /^[[:space:]]+[0-9]+x[0-9]+/ {
            match($0, /[0-9]+x[0-9]+/)
            res = substr($0, RSTART, RLENGTH)
            if (first == "") first = res
            if ($0 ~ /\+/) { pref = res; exit }
        }
        END { if (pref != "") print pref; else if (first != "") print first }
    '
}

# Prints the rate to drive a resolution at on an output: the lowest rate that
# still meets the target fps, so the panel is not pushed harder than the
# stream needs, falling back to the highest rate the mode offers when nothing
# reaches the target. The half-hertz tolerance is what lets a 60fps request
# settle on a 59.81Hz or 59.95Hz mode instead of jumping to 120.
best_rate_for() {
    local output="$1" res="$2" target="$3"
    list_output_modes "$output" | awk -v res="$res" -v target="$target" '
        $1 == res {
            rs = $2; r = rs + 0
            if (maxs == "" || r > maxn) { maxs = rs; maxn = r }
            if (r + 0.5 >= target && (bests == "" || r < bestn)) { bests = rs; bestn = r }
        }
        END { if (bests != "") print bests; else if (maxs != "") print maxs }
    '
}

# Prints the name of the currently primary connected output, falling back to
# the first connected output when no primary is set.
current_primary_output() {
    xrandr | awk '
        / connected primary / { print $1; exit }
        / connected / { if (fallback == "") fallback = $1 }
        END { if (fallback != "") print fallback }
    ' | head -1
}
