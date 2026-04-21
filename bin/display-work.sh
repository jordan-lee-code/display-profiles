#!/bin/bash
# Thin wrapper — switch to the 'work' profile
exec "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/display-switch.sh" work
