#!/bin/bash
set -euo pipefail
# Apply a display mode that matches what a streaming client asked for.
# Usage: display-switch-client.sh [--output NAME] [--fallback PROFILE]
#                                 [--width N --height N --fps N] [--dry-run]
#
# Sunshine exports SUNSHINE_CLIENT_WIDTH, SUNSHINE_CLIENT_HEIGHT and
# SUNSHINE_CLIENT_FPS into its prep-cmd environment, so a single Sunshine app
# entry can serve a Steam Deck at 1280x800, a TV at 3840x2160 and a laptop at
# 2560x1440 without a hardcoded profile for each one. The --width/--height/
# --fps flags override the environment and exist mainly for testing.
#
# Where the requested size is not one of the panel's own modes, the panel is
# left on its preferred mode and --scale-from gives X a framebuffer of the
# requested size instead. That matters more than it sounds: a Steam Deck asking
# for 1280x800 would otherwise pin the panel to the only 1280x800 mode it has,
# which is 59.81Hz, capping the stream at 60fps. Scaling keeps the panel at its
# full refresh so a 90fps stream is actually possible.
#
# This script deliberately does not write ~/.config/display-mode. A resolution
# picked to suit a remote client is not one you want restored at next login.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/common.sh"

require_cmd xrandr "Install with: sudo apt install x11-xserver-utils"

OUTPUT=""
FALLBACK=""
DRY_RUN=0
REQ_W="${SUNSHINE_CLIENT_WIDTH:-}"
REQ_H="${SUNSHINE_CLIENT_HEIGHT:-}"
REQ_FPS="${SUNSHINE_CLIENT_FPS:-}"

while (( $# )); do
    case "$1" in
        --output)   OUTPUT="${2:-}";   shift 2 ;;
        --fallback) FALLBACK="${2:-}"; shift 2 ;;
        --width)    REQ_W="${2:-}";    shift 2 ;;
        --height)   REQ_H="${2:-}";    shift 2 ;;
        --fps)      REQ_FPS="${2:-}";  shift 2 ;;
        --dry-run)  DRY_RUN=1;         shift ;;
        -h|--help)  sed -n '3,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Client-supplied numbers arrive over the network, so they are bounds-checked
# before they are ever handed to xrandr. The ceiling leaves room for an 8K
# client without letting a malformed value ask for an absurd framebuffer.
valid_int() {
    local v="$1" min="$2" max="$3"
    [[ "$v" =~ ^[0-9]+$ ]] && (( v >= min && v <= max ))
}

# True when a refresh rate meets a target fps. The half-hertz tolerance is what
# lets a 60fps request settle on a 59.81Hz or 59.95Hz mode rather than stepping
# the panel up to 120 for no benefit.
rate_meets() {
    awk -v r="$1" -v t="$2" 'BEGIN { exit !(r + 0.5 >= t) }'
}

# Fall back to a named profile when the client told us nothing usable, or leave
# the display alone entirely if no fallback was configured. Leaving it alone is
# the safer default: a stream at the current desktop resolution still works.
bail_to_fallback() {
    local reason="$1"
    if [[ -n "$FALLBACK" ]]; then
        echo "$reason — falling back to profile '$FALLBACK'"
        exec "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/display-switch.sh" "$FALLBACK"
    fi
    echo "$reason — leaving the current display configuration alone"
    exit 0
}

if ! valid_int "$REQ_W" 640 7680 || ! valid_int "$REQ_H" 480 4320; then
    bail_to_fallback "No usable client resolution (got '${REQ_W:-unset}x${REQ_H:-unset}')"
fi

# An absent or nonsensical fps is not worth failing over; 60 is the safe floor
# and the rate picker will still choose something the panel can actually do.
valid_int "$REQ_FPS" 1 1000 || REQ_FPS=60

# The output to stream from is read from a config file so it survives updates,
# and falls back to whichever output is currently primary.
STREAM_OUTPUT_FILE="$(get_profiles_dir)/stream-output"
if [[ -z "$OUTPUT" && -r "$STREAM_OUTPUT_FILE" ]]; then
    OUTPUT="$(tr -d '[:space:]' < "$STREAM_OUTPUT_FILE")"
fi
[[ -z "$OUTPUT" ]] && OUTPUT="$(current_primary_output)"

if [[ -z "$OUTPUT" ]]; then
    log_error "client mode found no connected output to stream from"
    echo "No connected output to stream from." >&2
    exit 1
fi

PANEL_RES="$(output_preferred_res "$OUTPUT")"
if [[ -z "$PANEL_RES" ]]; then
    bail_to_fallback "Output '$OUTPUT' is not connected"
fi

REQ_RES="${REQ_W}x${REQ_H}"

# Prefer a real mode at the requested size when one exists and is fast enough,
# because driving the panel natively avoids the scaler altogether. Otherwise
# hold the panel at its preferred mode and scale a framebuffer of the requested
# size onto it.
declare -a SCALE_ARGS
NATIVE_RATE="$(best_rate_for "$OUTPUT" "$REQ_RES" "$REQ_FPS")"
if [[ -n "$NATIVE_RATE" ]] && rate_meets "$NATIVE_RATE" "$REQ_FPS"; then
    MODE_RES="$REQ_RES"
    MODE_RATE="$NATIVE_RATE"
    SCALE_ARGS=(--scale 1x1)
    METHOD="native mode"
else
    MODE_RES="$PANEL_RES"
    MODE_RATE="$(best_rate_for "$OUTPUT" "$PANEL_RES" "$REQ_FPS")"
    if [[ "$REQ_RES" == "$PANEL_RES" ]]; then
        SCALE_ARGS=(--scale 1x1)
        METHOD="native mode"
    else
        SCALE_ARGS=(--scale-from "$REQ_RES")
        METHOD="scaled onto $PANEL_RES"
    fi
fi

if [[ -z "$MODE_RATE" ]]; then
    bail_to_fallback "Output '$OUTPUT' reported no usable refresh rate for $MODE_RES"
fi

# Everything other than the streaming output is switched off, so the captured
# framebuffer is exactly the client's screen and nothing else.
declare -a ARGS=()
while read -r other; do
    [[ -z "$other" ]] && continue
    if [[ "$other" == "$OUTPUT" ]]; then
        ARGS+=(--output "$other" --mode "$MODE_RES" --rate "$MODE_RATE"
               "${SCALE_ARGS[@]}" --pos 0x0 --primary)
    else
        ARGS+=(--output "$other" --off)
    fi
done < <(xrandr | awk '/ connected/{print $1}')

echo "Client asked for ${REQ_RES}@${REQ_FPS} — driving $OUTPUT at ${MODE_RES}@${MODE_RATE} ($METHOD)"

if (( DRY_RUN )); then
    printf 'xrandr'; printf ' %q' "${ARGS[@]}"; printf '\n'
    exit 0
fi

# Retry rather than fail outright. A switch requested while outputs are still
# settling, which is exactly when a stream starts, can lose a race that the
# same command wins a moment later.
attempt=1
while (( attempt <= 3 )); do
    if err=$(xrandr "${ARGS[@]}" 2>&1); then
        break
    fi
    log_error "client mode xrandr attempt $attempt/3 failed: ${err:-no error output}"
    if (( attempt == 3 )); then
        echo "xrandr failed after 3 attempts. See $(get_log_file) for details." >&2
        exit 1
    fi
    sleep 1
    (( attempt++ ))
done

# Confirm the framebuffer really is the size the client asked for, because
# xrandr can succeed while silently landing on something else.
ACTUAL="$(xrandr | awk '/^Screen/ { print $8 "x" substr($10, 1, length($10)-1); exit }')"
if [[ "$ACTUAL" != "$REQ_RES" ]]; then
    log_error "client mode wanted $REQ_RES but the screen reports $ACTUAL"
    echo "Warning: screen is $ACTUAL, not the requested $REQ_RES." >&2
fi

echo "Done."
