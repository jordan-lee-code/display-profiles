#!/bin/bash
# Discover connected outputs, available modes, and saved profiles

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

echo "Connected outputs:"
echo ""

xrandr | awk '
/^[A-Z].*[[:space:]]connected[[:space:]]/ {
    output = $1
    primary = ($0 ~ /primary/) ? " (primary)" : ""
    match($0, /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/)
    current = (RSTART > 0) ? substr($0, RSTART, index(substr($0, RSTART), "+") - 1) : ""
    printf "  %-12s connected%s%s\n", output, primary, (current ? "  current: " current : "")
    in_output = 1
    next
}
/^[A-Z].*[[:space:]]disconnected/ { in_output = 0; next }
/^[A-Z]/ { in_output = 0; next }
in_output && /^[[:space:]]+[0-9]+x[0-9]+/ {
    res = $1
    rates = ""
    for (i = 2; i <= NF; i++) {
        r = $i; gsub(/[*+]/, "", r)
        if (r ~ /^[0-9]+\.[0-9]+$/) {
            marker = ($i ~ /\*/) ? "*" : ($i ~ /\+/) ? "+" : " "
            rates = rates "  " r marker
        }
    }
    printf "    %-16s %s\n", res, rates
}
'

echo ""
echo "Saved profiles:"
echo ""

mapfile -t profiles < <(list_profiles)
if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "  No profiles yet. Run: display-new-profile.sh"
else
    for p in "${profiles[@]}"; do
        dir="$(get_profiles_dir)/$p"
        desc=""
        [[ -f "$dir/meta" ]] && desc=$(grep ^DESCRIPTION= "$dir/meta" 2>/dev/null | cut -d= -f2-)
        printf "  %-16s %s\n" "$p" "${desc:-$dir}"
    done
fi
echo ""
