#!/bin/bash
# Thin wrapper — switch to the 'personal' profile
exec "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/display-switch.sh" personal
