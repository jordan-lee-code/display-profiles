#!/bin/bash
# Install display-profiles to the current user's environment

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing display-profiles..."

# Scripts
mkdir -p "$HOME/bin"
for f in "$REPO_DIR"/bin/display-*.sh; do
    ln -sf "$f" "$HOME/bin/$(basename "$f")"
done
echo "  Scripts symlinked to ~/bin/"

# Autostart — generated with real HOME path (desktop files can't expand ~)
mkdir -p "$HOME/.config/autostart"
sed "s|%%HOME%%|$HOME|g" "$REPO_DIR/desktop/display-apply.desktop" \
    > "$HOME/.config/autostart/display-apply.desktop"
echo "  Autostart entry installed to ~/.config/autostart/"

# Shutdown launcher
mkdir -p "$HOME/.local/share/applications"
sed "s|%%HOME%%|$HOME|g" "$REPO_DIR/desktop/display-shutdown.desktop" \
    > "$HOME/.local/share/applications/display-shutdown.desktop"
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
echo "  Shutdown launcher installed to ~/.local/share/applications/"

# Default profiles
PROFILES_DIR="$HOME/.config/display-profiles"
if [[ ! -d "$PROFILES_DIR/work" ]] && [[ ! -d "$PROFILES_DIR/personal" ]]; then
    echo ""
    echo "  No profiles found. Run display-setup.sh to discover your outputs,"
    echo "  then display-new-profile.sh to create profiles interactively."
else
    echo "  Existing profiles preserved in $PROFILES_DIR"
fi

# PATH reminder
if ! echo "$PATH" | tr ':' '\n' | grep -q "$HOME/bin"; then
    echo ""
    echo "  Note: ~/bin is not in your PATH. Add this to ~/.bashrc:"
    echo "    export PATH=\"\$HOME/bin:\$PATH\""
fi

echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
echo "  display-setup.sh          — see connected outputs and saved profiles"
echo "  display-new-profile.sh    — create a new profile interactively"
echo "  display-switch.sh <name>  — apply a profile"
echo "  display-save-layout.sh <name>  — save current panel layout to a profile"
