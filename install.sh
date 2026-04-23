#!/bin/bash
# Install display-profiles for the current user.
#
# Scripts are symlinked rather than copied so that edits in the repo take
# effect immediately without reinstalling. The desktop files cannot be
# symlinked because they contain a %%HOME%% placeholder that must be
# substituted with the real path — desktop file parsers do not expand
# shell variables or ~.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing display-profiles..."

# Symlink every bin/display-*.sh into ~/bin/
mkdir -p "$HOME/bin"
for f in "$REPO_DIR"/bin/display-*.sh; do
    ln -sf "$f" "$HOME/bin/$(basename "$f")"
done
echo "  Scripts symlinked to ~/bin/"

# Wire git hooks so the pre-push version bump hook is active for contributors.
if git -C "$REPO_DIR" config core.hooksPath .githooks 2>/dev/null; then
    echo "  Git hooks configured (.githooks/)"
fi

# Generate the autostart entry with the real HOME path substituted in.
# Autostart files must use absolute paths — the desktop file spec does not
# support ~ or $HOME in the Exec field.
mkdir -p "$HOME/.config/autostart"
sed "s|%%HOME%%|$HOME|g" "$REPO_DIR/desktop/display-apply.desktop" \
    > "$HOME/.config/autostart/display-apply.desktop"
echo "  Autostart entry installed to ~/.config/autostart/"

# First-run hint if no profiles exist yet.
PROFILES_DIR="$HOME/.config/display-profiles"
if [[ ! -d "$PROFILES_DIR" ]] || [[ -z "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]]; then
    echo ""
    echo "  No profiles found. Run display-setup.sh to discover your outputs,"
    echo "  then display-new-profile.sh to create profiles interactively."
else
    echo "  Existing profiles preserved in $PROFILES_DIR"
fi

# Warn if ~/bin is not on PATH — scripts won't be callable by name without it.
if ! echo "$PATH" | tr ':' '\n' | grep -q "$HOME/bin"; then
    echo ""
    echo "  Note: ~/bin is not in your PATH. Add this to ~/.bashrc:"
    echo "    export PATH=\"\$HOME/bin:\$PATH\""
fi

echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
echo "  display-setup.sh               — see connected outputs and saved profiles"
echo "  display-new-profile.sh         — create a new profile interactively"
echo "  display-switch.sh <name>       — apply a profile"
echo "  display-save-layout.sh <name>  — save current panel layout to a profile"
