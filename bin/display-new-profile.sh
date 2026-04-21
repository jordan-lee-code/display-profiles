#!/bin/bash
# Interactive wizard to create a new named display profile

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
declare -A MODE
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

    MODE[$OUTPUT]="$SELECTED_RES"
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

# --- Positions for non-primary outputs ---
declare -A POSITION
if [[ ${#ENABLED_LIST[@]} -gt 1 ]]; then
    echo ""
    echo "Position outputs relative to $PRIMARY:"
    for OUTPUT in "${ENABLED_LIST[@]}"; do
        [[ "$OUTPUT" == "$PRIMARY" ]] && continue
        echo "  $OUTPUT:"
        echo "    1. Left of $PRIMARY"
        echo "    2. Right of $PRIMARY"
        echo "    3. Above $PRIMARY"
        echo "    4. Below $PRIMARY"
        read -rp "  Position [2]: " idx; idx="${idx:-2}"
        case "$idx" in
            1) POSITION[$OUTPUT]="--left-of $PRIMARY"  ;;
            3) POSITION[$OUTPUT]="--above $PRIMARY"    ;;
            4) POSITION[$OUTPUT]="--below $PRIMARY"    ;;
            *) POSITION[$OUTPUT]="--right-of $PRIMARY" ;;
        esac
    done
fi

# --- Generate xrandr.sh ---
{
    echo "#!/bin/bash"
    printf "xrandr"
    for OUTPUT in "${ALL_OUTPUTS[@]}"; do
        if [[ -v ENABLED[$OUTPUT] ]]; then
            printf " \\\\\n    --output %s --mode %s --rate %s" \
                "$OUTPUT" "${MODE[$OUTPUT]}" "${RATE[$OUTPUT]}"
            [[ "$OUTPUT" == "$PRIMARY" ]] && printf " --primary"
            [[ -v POSITION[$OUTPUT] ]] && printf " %s" "${POSITION[$OUTPUT]}"
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
