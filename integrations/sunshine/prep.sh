#!/bin/sh
# Sunshine prep-cmd bridge. This runs INSIDE the Sunshine flatpak sandbox,
# not on the host.
#
# Sunshine exports SUNSHINE_CLIENT_WIDTH, SUNSHINE_CLIENT_HEIGHT and
# SUNSHINE_CLIENT_FPS into its prep-cmd environment, but flatpak-spawn --host
# deliberately does not carry the sandbox environment across to the host, so
# the values have to be handed over one at a time with --env. Passing them is
# the only reason this wrapper exists; everything else happens on the host in
# display-switch-client.sh.
#
# Wire it into Sunshine's apps.json as:
#   "do":   "sh /home/<you>/bin/sunshine-display-prep.sh do"
#   "undo": "sh /home/<you>/bin/sunshine-display-prep.sh undo"
#
# Set SUNSHINE_UNDO_PROFILE in the Sunshine flatpak environment to choose the
# layout to come back to when the stream ends. It defaults to 'personal'.
#
# Any further arguments are passed straight through to the host script, which
# makes the whole path testable with 'do --dry-run'.

UNDO_PROFILE="${SUNSHINE_UNDO_PROFILE:-personal}"

case "${1:-}" in
    do)
        shift
        # No --fallback here on purpose. If a client tells us nothing usable,
        # leaving the desktop exactly as it is still gives a working stream,
        # which is kinder than forcing a layout change nobody asked for.
        exec flatpak-spawn --host \
            --env=SUNSHINE_CLIENT_WIDTH="${SUNSHINE_CLIENT_WIDTH:-}" \
            --env=SUNSHINE_CLIENT_HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-}" \
            --env=SUNSHINE_CLIENT_FPS="${SUNSHINE_CLIENT_FPS:-}" \
            display-switch-client.sh "$@"
        ;;
    undo)
        shift
        exec flatpak-spawn --host display-switch.sh "$UNDO_PROFILE" "$@"
        ;;
    *)
        echo "Usage: $(basename "$0") do|undo" >&2
        exit 1
        ;;
esac
