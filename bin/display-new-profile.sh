#!/bin/bash
set -euo pipefail
# Interactive wizard to create a new named display profile.
#
# Walks through: profile name, enable/disable each output, resolution, refresh
# rate, primary selection, and multi-monitor positioning. Positions are tracked
# as absolute pixel coordinates so any layout (including centered arrangements)
# can be expressed. The generated xrandr.sh uses --pos rather than relative
# flags like --left-of, which cannot represent centering.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

require_cmd xrandr "Install with: sudo apt install x11-xserver-utils"

# --- Script-scope array declarations ---
# Populated by the functions below; declared at script scope so each function
# can read and write them without local scope restrictions.
declare -A ENABLED          # output → 1 if the user chose to enable it
declare -A MODE_W           # output → selected width in pixels
declare -A MODE_H           # output → selected height in pixels
declare -A RATE             # output → selected refresh rate (Hz)
declare -A POS_X            # output → final absolute x position
declare -A POS_Y            # output → final absolute y position
declare -a ALL_OUTPUTS      # all connected xrandr outputs (discovered order)
declare -a ENABLED_LIST     # enabled outputs sorted alphabetically
declare -a POSITIONED       # outputs that have been assigned a position so far

# --- discover_outputs ---
# Populate ALL_OUTPUTS and print a numbered list of connected monitors.
discover_outputs() {
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
}

# --- select_resolutions ---
# For each output, ask whether to enable it, then pick a resolution and refresh rate.
# Populates ENABLED, MODE_W, MODE_H, RATE.
select_resolutions() {
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
        pick_index idx "${#RESOLUTIONS[@]}" "  Select [1-${#RESOLUTIONS[@]}]: "
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
        pick_index idx "${#RATES[@]}" "  Select [1-${#RATES[@]}]: "
        RATE[$OUTPUT]="${RATES[$((idx-1))]}"
    done
}

# --- calculate_positions ---
# Ask the user to pick a primary output, then interactively place every other
# enabled output in pixel space. The primary is anchored at (0,0).
# Populates PRIMARY, ENABLED_LIST, POS_X, POS_Y, POSITIONED.
#
# All coordinates are integers (bash does not support floats); centering uses
# integer division, which may be off by one pixel on odd-width differences —
# acceptable for display use.
calculate_positions() {
    mapfile -t ENABLED_LIST < <(printf '%s\n' "${!ENABLED[@]}" | sort)
    if [[ ${#ENABLED_LIST[@]} -eq 0 ]]; then
        echo "No outputs enabled — nothing to save." >&2; exit 1
    fi

    echo ""
    PRIMARY="${ENABLED_LIST[0]}"
    if [[ ${#ENABLED_LIST[@]} -gt 1 ]]; then
        echo "Select primary output:"
        for i in "${!ENABLED_LIST[@]}"; do echo "  $((i+1)). ${ENABLED_LIST[$i]}"; done
        pick_index idx "${#ENABLED_LIST[@]}" "  Primary [1-${#ENABLED_LIST[@]}]: "
        PRIMARY="${ENABLED_LIST[$((idx-1))]}"
    fi

    POS_X[$PRIMARY]=0
    POS_Y[$PRIMARY]=0
    POSITIONED=("$PRIMARY")

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
            ref_w=${MODE_W[$REF]}
            ref_h=${MODE_H[$REF]}
            ref_x=${POS_X[$REF]}
            ref_y=${POS_Y[$REF]}
            out_w=${MODE_W[$OUTPUT]}
            out_h=${MODE_H[$OUTPUT]}

            # Left: output starts where REF starts, shifted left by output width.
            OPT_LABELS+=("Left of $REF")
            OPT_X+=($((ref_x - out_w)))
            OPT_Y+=($ref_y)

            # Right: output starts at the right edge of REF.
            OPT_LABELS+=("Right of $REF")
            OPT_X+=($((ref_x + ref_w)))
            OPT_Y+=($ref_y)

            # Above: output bottom edge aligns with REF top edge.
            OPT_LABELS+=("Above $REF")
            OPT_X+=($ref_x)
            OPT_Y+=($((ref_y - out_h)))

            # Below: output top edge aligns with REF bottom edge.
            OPT_LABELS+=("Below $REF")
            OPT_X+=($ref_x)
            OPT_Y+=($((ref_y + ref_h)))

            # Centered above: horizontally centred over REF, above it.
            OPT_LABELS+=("Centered above $REF")
            OPT_X+=($((ref_x + (ref_w - out_w) / 2)))
            OPT_Y+=($((ref_y - out_h)))

            # Centered below: horizontally centred over REF, below it.
            OPT_LABELS+=("Centered below $REF")
            OPT_X+=($((ref_x + (ref_w - out_w) / 2)))
            OPT_Y+=($((ref_y + ref_h)))
        done

        # Bounding-box centering: compute the pixel extent of all placed outputs so we can
        # offer centred-over-all options in addition to centred-over-one options.
        # bound_min_x/y = top-left corner of the group; bound_max_x/y = far right/bottom edge.
        if [[ ${#POSITIONED[@]} -ge 2 ]]; then
            bound_min_x=999999; bound_max_x=0; bound_min_y=999999; bound_max_y=0
            for REF in "${POSITIONED[@]}"; do
                x=${POS_X[$REF]}; y=${POS_Y[$REF]}
                ref_right_x=$((x + MODE_W[$REF])); ref_bottom_y=$((y + MODE_H[$REF]))
                (( x             < bound_min_x )) && bound_min_x=$x
                (( ref_right_x  > bound_max_x )) && bound_max_x=$ref_right_x
                (( y             < bound_min_y )) && bound_min_y=$y
                (( ref_bottom_y > bound_max_y )) && bound_max_y=$ref_bottom_y
            done
            bound_total_w=$((bound_max_x - bound_min_x))
            out_w=${MODE_W[$OUTPUT]}
            out_h=${MODE_H[$OUTPUT]}

            OPT_LABELS+=("Centered above all screens")
            OPT_X+=($((bound_min_x + (bound_total_w - out_w) / 2)))
            OPT_Y+=($((bound_min_y - out_h)))

            OPT_LABELS+=("Centered below all screens")
            OPT_X+=($((bound_min_x + (bound_total_w - out_w) / 2)))
            OPT_Y+=($bound_max_y)
        fi

        for i in "${!OPT_LABELS[@]}"; do
            echo "  $((i+1)). ${OPT_LABELS[$i]}"
        done
        pick_index idx "${#OPT_LABELS[@]}" "  Position [1-${#OPT_LABELS[@]}]: "
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
}

# --- render_layout_preview ---
# Draw an ASCII box diagram of the final layout scaled to a fixed character grid,
# then print a pixel coordinate summary underneath.
render_layout_preview() {
    echo ""
    echo "Layout preview:"
    echo ""

    # Compute the total pixel bounding box so coordinates can be scaled to grid space.
    max_x=0; max_y=0
    for OUTPUT in "${ENABLED_LIST[@]}"; do
        rx=$((POS_X[$OUTPUT] + MODE_W[$OUTPUT]))
        ry=$((POS_Y[$OUTPUT] + MODE_H[$OUTPUT]))
        (( rx > max_x )) && max_x=$rx
        (( ry > max_y )) && max_y=$ry
    done

    # Grid dimensions chosen to fit the preview in a standard 80-column terminal with a 2-space indent.
    GRID_COLS=60; GRID_ROWS=12
    declare -a GRID
    for ((row=0; row<GRID_ROWS; row++)); do
        line=""
        for ((col=0; col<GRID_COLS; col++)); do line+=" "; done
        GRID[$row]="$line"
    done

    for OUTPUT in "${ENABLED_LIST[@]}"; do
        x=${POS_X[$OUTPUT]}; y=${POS_Y[$OUTPUT]}
        w=${MODE_W[$OUTPUT]}; h=${MODE_H[$OUTPUT]}

        # Scale pixel coordinates down to grid coordinates.
        grid_x=$(( x * GRID_COLS / max_x ))
        grid_y=$(( y * GRID_ROWS / max_y ))
        grid_w=$(( w * GRID_COLS / max_x ))
        grid_h=$(( h * GRID_ROWS / max_y ))
        [[ $grid_w -lt 5 ]] && grid_w=5
        [[ $grid_h -lt 3 ]] && grid_h=3

        label="$OUTPUT"
        [[ "$OUTPUT" == "$PRIMARY" ]] && label+="*"

        for ((row=grid_y; row<grid_y+grid_h && row<GRID_ROWS; row++)); do
            line="${GRID[$row]}"
            # Splice this output's box into the existing grid row using string slicing:
            #   ${line:0:$grid_x}             — unchanged columns before the output's left edge
            #   +${border}+  or  |${inner}|  — top/bottom border row or labelled interior row
            #   ${line:$((grid_x+grid_w+2))} — unchanged columns after the right edge
            #   (+2 accounts for the two border characters flanking the content)
            if (( row == grid_y || row == grid_y+grid_h-1 )); then
                border=""
                for ((col=0; col<grid_w; col++)); do border+="-"; done
                line="${line:0:$grid_x}+${border}+${line:$((grid_x+grid_w+2))}"
            else
                inner="$(printf "%-${grid_w}s" "")"
                if (( row == grid_y + grid_h/2 )); then
                    label_len=${#label}
                    label_pad=$(( (grid_w - label_len) / 2 ))
                    inner="$(printf "%${label_pad}s%s%-$((grid_w - label_pad - label_len))s" "" "$label" "")"
                fi
                line="${line:0:$grid_x}|${inner}|${line:$((grid_x+grid_w+2))}"
            fi
            GRID[$row]="$line"
        done
    done

    for ((row=0; row<GRID_ROWS; row++)); do
        echo "  ${GRID[$row]}"
    done
    echo "  (* = primary)"
    echo ""

    # Pixel coordinate summary.
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
}

# --- write_profile ---
# Write xrandr.sh, metadata, an optional desktop launcher, and an optional
# panel layout snapshot into PROFILE_DIR.
write_profile() {
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

    read -rp "Profile description (optional): " DESC
    {
        echo "NAME=$PROFILE_NAME"
        echo "DESCRIPTION=${DESC:-}"
        echo "CREATED=$(date -Iseconds)"
    } > "$PROFILE_DIR/meta"

    echo ""
    echo "Profile '$PROFILE_NAME' created."

    read -rp "Create start menu shortcut? [Y/n] " yn
    if [[ "${yn,,}" != "n" ]]; then
        DESKTOP_FILE="$HOME/.local/share/applications/display-${PROFILE_NAME}.desktop"
        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=${PROFILE_NAME^} Displays
Comment=${DESC:-Switch to $PROFILE_NAME display profile}
Exec=$HOME/bin/display-switch.sh "$PROFILE_NAME"
Icon=video-display-symbolic
Terminal=false
Categories=Settings;HardwareSettings;
Keywords=display;monitor;$PROFILE_NAME;screen;
EOF
        update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
        echo "  Start menu shortcut created."
    fi

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
}

# --- Profile name ---
read -rp "Profile name: " PROFILE_NAME
ORIGINAL_NAME="$PROFILE_NAME"
PROFILE_NAME="${PROFILE_NAME// /-}"
[[ -z "$PROFILE_NAME" ]] && { echo "Profile name required." >&2; exit 1; }
[[ "$PROFILE_NAME" != "$ORIGINAL_NAME" ]] && echo "  Profile name saved as '$PROFILE_NAME'."

PROFILE_DIR="$(get_profiles_dir)/$PROFILE_NAME"
if [[ -d "$PROFILE_DIR" ]]; then
    read -rp "Profile '$PROFILE_NAME' already exists. Overwrite? [y/N] " yn
    [[ "${yn,,}" != "y" ]] && exit 0
fi
mkdir -p "$PROFILE_DIR"

discover_outputs
select_resolutions
calculate_positions
render_layout_preview
write_profile
