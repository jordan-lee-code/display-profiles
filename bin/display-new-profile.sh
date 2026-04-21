#!/bin/bash
# Interactive wizard to create a new named display profile.
#
# Walks through: profile name, enable/disable each output, resolution, refresh
# rate, primary selection, and multi-monitor positioning. Positions are tracked
# as absolute pixel coordinates so any layout (including centered arrangements)
# can be expressed. The generated xrandr.sh uses --pos rather than relative
# flags like --left-of, which cannot represent centering.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

# --- Profile name ---
read -rp "Profile name: " PROFILE_NAME
PROFILE_NAME="${PROFILE_NAME// /-}"
[[ -z "$PROFILE_NAME" ]] && { echo "Profile name required." >&2; exit 1; }

PROFILE_DIR="$(get_profiles_dir)/$PROFILE_NAME"
if [[ -d "$PROFILE_DIR" ]]; then
    read -rp "Profile '$PROFILE_NAME' already exists. Overwrite? [y/N] " yn
    [[ "${yn,,}" != "y" ]] && exit 0
fi
mkdir -p "$PROFILE_DIR"

# --- Discover outputs ---
mapfile -t ALL_OUTPUTS < <(xrandr | awk '/ connected/{print $1}')
if [[ ${#ALL_OUTPUTS[@]} -eq 0 ]]; then
    echo "No connected outputs found." >&2; exit 1
fi

echo ""
echo "Connected outputs:"
for i in "${!ALL_OUTPUTS[@]}"; do
    echo "  $((i+1)). ${ALL_OUTPUTS[$i]}"
done
echo ""

# --- Configure each output ---
declare -A ENABLED
declare -A MODE_W   # width in pixels
declare -A MODE_H   # height in pixels
declare -A RATE

for OUTPUT in "${ALL_OUTPUTS[@]}"; do
    read -rp "Enable $OUTPUT? [Y/n] " yn
    [[ "${yn,,}" == "n" ]] && continue
    ENABLED[$OUTPUT]=1

    mapfile -t RESOLUTIONS < <(xrandr | awk -v out="$OUTPUT" '
        $0 ~ "^"out" connected" { found=1; next }
        found && /^[A-Z]/ { exit }
        found && /^[[:space:]]+[0-9]+x[0-9]+/ {
            match($0, /[0-9]+x[0-9]+/)
            res = substr($0, RSTART, RLENGTH)
            if (!seen[res]++) print res
        }
    ')

    echo "  Available resolutions:"
    for i in "${!RESOLUTIONS[@]}"; do echo "    $((i+1)). ${RESOLUTIONS[$i]}"; done
    read -rp "  Select [1]: " idx; idx="${idx:-1}"
    SELECTED_RES="${RESOLUTIONS[$((idx-1))]}"

    # Split "WxH" into separate integers for later arithmetic.
    IFS='x' read -r w h <<< "$SELECTED_RES"
    MODE_W[$OUTPUT]="$w"
    MODE_H[$OUTPUT]="$h"

    mapfile -t RATES < <(xrandr | awk -v out="$OUTPUT" -v res="$SELECTED_RES" '
        $0 ~ "^"out" connected" { found=1; next }
        found && /^[A-Z]/ { exit }
        found && $0 ~ "^[[:space:]]+"res {
            for (i=2; i<=NF; i++) {
                r = $i; gsub(/[*+]/, "", r)
                if (r ~ /^[0-9]+\.[0-9]+$/) print r
            }
        }
    ')

    echo "  Available refresh rates for $SELECTED_RES:"
    for i in "${!RATES[@]}"; do echo "    $((i+1)). ${RATES[$i]}Hz"; done
    read -rp "  Select [1]: " idx; idx="${idx:-1}"
    RATE[$OUTPUT]="${RATES[$((idx-1))]}"
done

# --- Primary output ---
mapfile -t ENABLED_LIST < <(printf '%s\n' "${!ENABLED[@]}" | sort)
if [[ ${#ENABLED_LIST[@]} -eq 0 ]]; then
    echo "No outputs enabled — nothing to save." >&2; exit 1
fi

echo ""
PRIMARY="${ENABLED_LIST[0]}"
if [[ ${#ENABLED_LIST[@]} -gt 1 ]]; then
    echo "Select primary output:"
    for i in "${!ENABLED_LIST[@]}"; do echo "  $((i+1)). ${ENABLED_LIST[$i]}"; done
    read -rp "  Primary [1]: " idx; idx="${idx:-1}"
    PRIMARY="${ENABLED_LIST[$((idx-1))]}"
fi

# --- Absolute position tracking ---
# The primary is anchored at (0,0). Every other output is placed relative to
# an already-positioned output using calculated pixel offsets. All coordinates
# are integers (bash does not support floats); centering uses integer division,
# which may be off by one pixel on odd-width differences — acceptable for display use.
declare -A POS_X
declare -A POS_Y
declare -a POSITIONED

POS_X[$PRIMARY]=0
POS_Y[$PRIMARY]=0
POSITIONED=("$PRIMARY")

# --- Position remaining enabled outputs ---
for OUTPUT in "${ENABLED_LIST[@]}"; do
    [[ "$OUTPUT" == "$PRIMARY" ]] && continue

    echo ""
    echo "Position $OUTPUT (${MODE_W[$OUTPUT]}x${MODE_H[$OUTPUT]}):"

    # Build a dynamic option list against every already-placed output.
    # Six spatial options are offered per reference output, plus two
    # bounding-box options (centered above/below all) once 2+ are placed.
    declare -a OPT_LABELS=()
    declare -a OPT_X=()
    declare -a OPT_Y=()

    for REF in "${POSITIONED[@]}"; do
        RW=${MODE_W[$REF]}
        RH=${MODE_H[$REF]}
        RX=${POS_X[$REF]}
        RY=${POS_Y[$REF]}
        OW=${MODE_W[$OUTPUT]}
        OH=${MODE_H[$OUTPUT]}

        # Left: output starts where REF starts, shifted left by output width.
        OPT_LABELS+=("Left of $REF")
        OPT_X+=($((RX - OW)))
        OPT_Y+=($RY)

        # Right: output starts at the right edge of REF.
        OPT_LABELS+=("Right of $REF")
        OPT_X+=($((RX + RW)))
        OPT_Y+=($RY)

        # Above: output bottom edge aligns with REF top edge.
        OPT_LABELS+=("Above $REF")
        OPT_X+=($RX)
        OPT_Y+=($((RY - OH)))

        # Below: output top edge aligns with REF bottom edge.
        OPT_LABELS+=("Below $REF")
        OPT_X+=($RX)
        OPT_Y+=($((RY + RH)))

        # Centered above: horizontally centred over REF, above it.
        OPT_LABELS+=("Centered above $REF")
        OPT_X+=($((RX + (RW - OW) / 2)))
        OPT_Y+=($((RY - OH)))

        # Centered below: horizontally centred over REF, below it.
        OPT_LABELS+=("Centered below $REF")
        OPT_X+=($((RX + (RW - OW) / 2)))
        OPT_Y+=($((RY + RH)))
    done

    # Bounding-box centering: compute the pixel extent of all placed outputs,
    # then centre the new output over the whole group.
    if [[ ${#POSITIONED[@]} -ge 2 ]]; then
        min_bx=999999; max_bx=0; min_by=999999; max_by=0
        for REF in "${POSITIONED[@]}"; do
            x=${POS_X[$REF]}; y=${POS_Y[$REF]}
            rx=$((x + MODE_W[$REF])); ry=$((y + MODE_H[$REF]))
            (( x  < min_bx )) && min_bx=$x
            (( rx > max_bx )) && max_bx=$rx
            (( y  < min_by )) && min_by=$y
            (( ry > max_by )) && max_by=$ry
        done
        total_w=$((max_bx - min_bx))
        OW=${MODE_W[$OUTPUT]}
        OH=${MODE_H[$OUTPUT]}

        OPT_LABELS+=("Centered above all screens")
        OPT_X+=($((min_bx + (total_w - OW) / 2)))
        OPT_Y+=($((min_by - OH)))

        OPT_LABELS+=("Centered below all screens")
        OPT_X+=($((min_bx + (total_w - OW) / 2)))
        OPT_Y+=($max_by)
    fi

    for i in "${!OPT_LABELS[@]}"; do
        echo "  $((i+1)). ${OPT_LABELS[$i]}"
    done
    read -rp "  Position [1]: " idx; idx="${idx:-1}"
    chosen=$((idx - 1))

    POS_X[$OUTPUT]="${OPT_X[$chosen]}"
    POS_Y[$OUTPUT]="${OPT_Y[$chosen]}"
    POSITIONED+=("$OUTPUT")

    # Reset option arrays for the next output.
    unset OPT_LABELS OPT_X OPT_Y
    declare -a OPT_LABELS=()
    declare -a OPT_X=()
    declare -a OPT_Y=()
done

# --- Normalize coordinates ---
# Placements to the left of or above the primary produce negative coordinates.
# xrandr accepts negative positions but they behave unpredictably on some
# drivers, so shift the whole layout so the minimum x and y are both zero.
min_x=999999; min_y=999999
for OUTPUT in "${ENABLED_LIST[@]}"; do
    (( POS_X[$OUTPUT] < min_x )) && min_x=${POS_X[$OUTPUT]}
    (( POS_Y[$OUTPUT] < min_y )) && min_y=${POS_Y[$OUTPUT]}
done
for OUTPUT in "${ENABLED_LIST[@]}"; do
    POS_X[$OUTPUT]=$(( POS_X[$OUTPUT] - min_x ))
    POS_Y[$OUTPUT]=$(( POS_Y[$OUTPUT] - min_y ))
done

# --- Layout preview ---
# Compute the total bounding box so the ASCII diagram can be scaled to fit
# in a fixed 60x12 character grid. Each output is drawn as a labelled box.
echo ""
echo "Layout preview:"
echo ""

max_x=0; max_y=0
for OUTPUT in "${ENABLED_LIST[@]}"; do
    rx=$((POS_X[$OUTPUT] + MODE_W[$OUTPUT]))
    ry=$((POS_Y[$OUTPUT] + MODE_H[$OUTPUT]))
    (( rx > max_x )) && max_x=$rx
    (( ry > max_y )) && max_y=$ry
done

COLS=60; ROWS=12
declare -a GRID
for ((r=0; r<ROWS; r++)); do
    line=""
    for ((c=0; c<COLS; c++)); do line+=" "; done
    GRID[$r]="$line"
done

for OUTPUT in "${ENABLED_LIST[@]}"; do
    x=${POS_X[$OUTPUT]}; y=${POS_Y[$OUTPUT]}
    w=${MODE_W[$OUTPUT]}; h=${MODE_H[$OUTPUT]}

    # Scale pixel coordinates down to grid coordinates.
    gx=$(( x * COLS / max_x ))
    gy=$(( y * ROWS / max_y ))
    gw=$(( w * COLS / max_x ))
    gh=$(( h * ROWS / max_y ))
    [[ $gw -lt 5 ]] && gw=5
    [[ $gh -lt 3 ]] && gh=3

    label="$OUTPUT"
    [[ "$OUTPUT" == "$PRIMARY" ]] && label+="*"

    for ((r=gy; r<gy+gh && r<ROWS; r++)); do
        line="${GRID[$r]}"
        if (( r == gy || r == gy+gh-1 )); then
            border=""
            for ((c=0; c<gw; c++)); do border+="-"; done
            line="${line:0:$gx}+${border}+${line:$((gx+gw+2))}"
        else
            inner="$(printf "%-${gw}s" "")"
            if (( r == gy + gh/2 )); then
                llen=${#label}
                lpad=$(( (gw - llen) / 2 ))
                inner="$(printf "%${lpad}s%s%-$((gw - lpad - llen))s" "" "$label" "")"
            fi
            line="${line:0:$gx}|${inner}|${line:$((gx+gw+2))}"
        fi
        GRID[$r]="$line"
    done
done

for ((r=0; r<ROWS; r++)); do
    echo "  ${GRID[$r]}"
done
echo "  (* = primary)"
echo ""

# Pixel coordinate summary alongside the diagram.
for OUTPUT in "${ENABLED_LIST[@]}"; do
    marker=""
    [[ "$OUTPUT" == "$PRIMARY" ]] && marker=" [PRIMARY]"
    printf "  %-10s  pos %sx%s,  size %sx%s%s\n" \
        "$OUTPUT" "${POS_X[$OUTPUT]}" "${POS_Y[$OUTPUT]}" \
        "${MODE_W[$OUTPUT]}" "${MODE_H[$OUTPUT]}" "$marker"
done
for OUTPUT in "${ALL_OUTPUTS[@]}"; do
    [[ -v ENABLED[$OUTPUT] ]] || echo "  $OUTPUT  off"
done
echo ""

# --- Generate xrandr.sh ---
# Uses --pos for absolute placement. --pos and --left-of/--right-of are
# mutually exclusive in xrandr; --pos is the only way to express layouts
# where outputs are not simply tiled edge-to-edge.
{
    echo "#!/bin/bash"
    printf "xrandr"
    for OUTPUT in "${ALL_OUTPUTS[@]}"; do
        if [[ -v ENABLED[$OUTPUT] ]]; then
            printf " \\\\\n    --output %s --mode %sx%s --rate %s --pos %sx%s" \
                "$OUTPUT" "${MODE_W[$OUTPUT]}" "${MODE_H[$OUTPUT]}" \
                "${RATE[$OUTPUT]}" "${POS_X[$OUTPUT]}" "${POS_Y[$OUTPUT]}"
            [[ "$OUTPUT" == "$PRIMARY" ]] && printf " --primary"
        else
            printf " \\\\\n    --output %s --off" "$OUTPUT"
        fi
    done
    echo ""
} > "$PROFILE_DIR/xrandr.sh"
chmod +x "$PROFILE_DIR/xrandr.sh"

# --- Metadata ---
read -rp "Profile description (optional): " DESC
{
    echo "NAME=$PROFILE_NAME"
    echo "DESCRIPTION=${DESC:-}"
    echo "CREATED=$(date -Iseconds)"
} > "$PROFILE_DIR/meta"

echo ""
echo "Profile '$PROFILE_NAME' created."

# --- Desktop launcher ---
read -rp "Create start menu shortcut? [Y/n] " yn
if [[ "${yn,,}" != "n" ]]; then
    DESKTOP_FILE="$HOME/.local/share/applications/display-${PROFILE_NAME}.desktop"
    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=${PROFILE_NAME^} Displays
Comment=${DESC:-Switch to $PROFILE_NAME display profile}
Exec=$HOME/bin/display-switch.sh $PROFILE_NAME
Icon=video-display-symbolic
Terminal=false
Categories=Settings;HardwareSettings;
Keywords=display;monitor;$PROFILE_NAME;screen;
EOF
    update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
    echo "  Start menu shortcut created."
fi

# --- Panel layout ---
DE=$(detect_de)
SAVE_HOOK="$(get_hooks_dir)/$DE/save-panels.sh"
if [[ -f "$SAVE_HOOK" ]]; then
    read -rp "Save current panel layout for this profile? [Y/n] " yn
    if [[ "${yn,,}" != "n" ]]; then
        bash "$SAVE_HOOK" "$PROFILE_DIR"
        echo "  Panel layout saved."
    fi
fi

echo ""
echo "Switch to this profile with:  display-switch.sh $PROFILE_NAME"
