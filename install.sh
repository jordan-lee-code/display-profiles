#!/bin/bash
# Install cinnamon-display-profiles to the current user's environment

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing cinnamon-display-profiles..."

# Scripts
mkdir -p "$HOME/bin"
for f in "$REPO_DIR"/bin/display-*.sh; do
    ln -sf "$f" "$HOME/bin/$(basename "$f")"
done
echo "  Scripts symlinked to ~/bin/"

# Start menu entries
mkdir -p "$HOME/.local/share/applications"
for f in display-work.desktop display-personal.desktop display-shutdown.desktop; do
    ln -sf "$REPO_DIR/desktop/$f" "$HOME/.local/share/applications/$f"
done
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
echo "  Desktop entries symlinked to ~/.local/share/applications/"

# Autostart
mkdir -p "$HOME/.config/autostart"
ln -sf "$REPO_DIR/desktop/display-apply.desktop" "$HOME/.config/autostart/display-apply.desktop"
echo "  Autostart entry symlinked to ~/.config/autostart/"

echo ""
echo "Installation complete. Next steps:"
echo ""
echo "  1. Edit ~/bin/display-work.sh and ~/bin/display-personal.sh to match"
echo "     your monitor output names (default: DP-0, DP-2) and resolution."
echo ""
echo "  2. Save your panel layouts:"
echo "       display-save-layout.sh personal   (while both screens are up)"
echo "       display-work.sh                   (switch to work mode)"
echo "       display-save-layout.sh work        (after arranging the panel)"
echo ""
echo "  3. Optional - Cinnamenu integration:"
CINNAMENU_JS="\$HOME/.local/share/cinnamon/applets/Cinnamenu@json/5.8/sidebar.js"
echo "     Edit $CINNAMENU_JS"
echo "     Replace ShutdownRemote() with:"
echo "       Util.spawnCommandLine('\$HOME/bin/display-shutdown.sh')"
echo "     Add a Restart button using:"
echo "       Util.spawnCommandLine('\$HOME/bin/display-restart.sh')"
echo "     Then reload Cinnamon: cinnamon --replace &"
