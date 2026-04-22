#!/bin/bash
# Save the current Cinnamon panel layout into a profile directory.
# Usage: save-panels.sh <profile-dir>
#
# Reads each relevant dconf key and writes a panel-layout.sh restore script
# into the profile directory. display-switch.sh sources that script on every
# profile switch to recreate the exact panel arrangement.
#
# Cinnamon retains config for every monitor it has ever seen in dconf,
# even when screens are physically off. This script counts currently active
# outputs via xrandr and strips any panel entries whose monitor index no
# longer exists, so a single-screen save does not restore a dual-screen layout.
#
# Keys captured:
#   panels-enabled      — which panels exist, which monitor, and their position
#   panels-height       — pixel height per panel
#   panels-autohide     — autohide setting per panel
#   panels-hide-delay   — delay before hiding (ms)
#   panels-show-delay   — delay before showing (ms)
#   enabled-applets     — which applets are loaded and on which panel/zone/slot
#   next-applet-id      — counter used when adding new applets; must match or
#                         new applets added later will collide with saved IDs

PROFILE_DIR="${1:-}"
[[ -z "$PROFILE_DIR" ]] && { echo "Usage: save-panels.sh <profile-dir>" >&2; exit 1; }

# Count outputs that are connected AND have an active mode (geometry present).
# If xrandr is unavailable or returns nothing usable, use a high sentinel so
# no filtering occurs and behaviour matches the original save.
ACTIVE_MONITORS=$(xrandr 2>/dev/null \
    | grep -cE "^[^ ]+ connected (primary )?[0-9]+x[0-9]+\+" || true)
[[ "$ACTIVE_MONITORS" =~ ^[0-9]+$ ]] && (( ACTIVE_MONITORS > 0 )) \
    || ACTIVE_MONITORS=999

# Parse a GLib array string ['a', 'b', 'c'] into one element per line.
_glib_to_lines() {
    sed "s/^\[//; s/\]$//" <<< "$1" | tr ',' '\n' | sed "s/^ *'//; s/' *$//"
}

# Read lines on stdin and emit a GLib array string.
_lines_to_glib() {
    local first=true out="["
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        $first || out+=", "
        out+="'$line'"
        first=false
    done
    echo "${out}]"
}

SAVE_FILE="$PROFILE_DIR/panel-layout.sh"
echo "#!/bin/bash" > "$SAVE_FILE"

# ── panels-enabled ────────────────────────────────────────────────────────────
# Format: ['panelID:monitorIndex:position', ...]
# Keep entries whose monitorIndex < ACTIVE_MONITORS and collect the surviving
# panel IDs so the other keys can be filtered consistently.
declare -a VALID_IDS=()
PANELS_RAW=$(dconf read /org/cinnamon/panels-enabled 2>/dev/null)
if [[ -n "$PANELS_RAW" ]]; then
    declare -a kept=()
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        panel_id="${entry%%:*}"
        monitor_idx="${entry#*:}"; monitor_idx="${monitor_idx%%:*}"
        if (( monitor_idx < ACTIVE_MONITORS )); then
            VALID_IDS+=("$panel_id")
            kept+=("$entry")
        fi
    done < <(_glib_to_lines "$PANELS_RAW")

    if [[ ${#kept[@]} -gt 0 ]]; then
        glib="["; first=true
        for e in "${kept[@]}"; do $first || glib+=", "; glib+="'$e'"; first=false; done
        glib+="]"
        printf 'dconf write /org/cinnamon/panels-enabled "%s"\n' "$glib" >> "$SAVE_FILE"
    fi
fi

# Return 0 if $1 is a panel ID that survived the monitor-index filter above.
_valid_panel() {
    local p; for p in "${VALID_IDS[@]}"; do [[ "$p" == "$1" ]] && return 0; done; return 1
}

# ── panel-indexed arrays ──────────────────────────────────────────────────────
# Format: ['panelID:value', ...]
for key in panels-height panels-autohide panels-hide-delay panels-show-delay; do
    val=$(dconf read /org/cinnamon/$key 2>/dev/null)
    [[ -z "$val" ]] && continue
    filtered=$(_glib_to_lines "$val" | while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        _valid_panel "${entry%%:*}" && echo "$entry"
    done | _lines_to_glib)
    printf 'dconf write /org/cinnamon/%s "%s"\n' "$key" "$filtered" >> "$SAVE_FILE"
done

# ── enabled-applets ───────────────────────────────────────────────────────────
# Format: ['panelN:zone:slot:applet:id', ...]
val=$(dconf read /org/cinnamon/enabled-applets 2>/dev/null)
if [[ -n "$val" ]]; then
    filtered=$(_glib_to_lines "$val" | while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        panel_part="${entry%%:*}"             # e.g. "panel1"
        _valid_panel "${panel_part#panel}" && echo "$entry"
    done | _lines_to_glib)
    printf 'dconf write /org/cinnamon/enabled-applets "%s"\n' "$filtered" >> "$SAVE_FILE"
fi

# ── next-applet-id ────────────────────────────────────────────────────────────
val=$(dconf read /org/cinnamon/next-applet-id 2>/dev/null)
[[ -n "$val" ]] && printf 'dconf write /org/cinnamon/next-applet-id %s\n' "$val" >> "$SAVE_FILE"

chmod +x "$SAVE_FILE"
