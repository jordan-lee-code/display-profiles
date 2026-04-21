#!/bin/bash
# Restart the Cinnamon compositor to apply panel layout changes

nohup cinnamon --replace >/dev/null 2>&1 &
disown
