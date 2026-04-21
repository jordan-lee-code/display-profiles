#!/bin/bash
# Restart the Cinnamon compositor to apply panel layout changes.
#
# cinnamon --replace must be run in the background and disowned so this
# script can exit cleanly — if we waited for it to finish, the calling
# script would hang indefinitely because --replace replaces the running
# compositor and never returns. nohup prevents SIGHUP from killing the
# new compositor process when the parent shell exits.

nohup cinnamon --replace >/dev/null 2>&1 &
disown
