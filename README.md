# display-profiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Switch between named display profiles on Linux — applying xrandr configuration, optional DE panel layouts, and persisting the active profile across reboots.

Built to work around the Nvidia driver bug that drops refresh rate and forgets display arrangement after mode changes, and for use with software KVMs like [Barrier](https://github.com/debauchee/barrier) where switching between work and personal use requires a different monitor layout each time.

## What it does

- Applies `xrandr` config (outputs, resolution, refresh rate, positions, primary)
- Saves and restores DE panel layouts per profile (Cinnamon supported; hooks for others)
- Prompts for the next profile at shutdown and restart via a Zenity dialog or terminal menu
- Applies the saved profile automatically on login via autostart
- Interactive wizard to create new profiles with output discovery

---

## Requirements

| Package | Purpose | Required |
|---------|---------|----------|
| `x11-xserver-utils` | Provides `xrandr` | Yes |
| `zenity` | GTK dialog for shutdown/restart prompts | No — falls back to terminal `select` |
| `dconf-tools` | Panel layout save/restore | Cinnamon only |

Install on Debian/Ubuntu/Mint:

```bash
sudo apt install x11-xserver-utils zenity dconf-tools
```

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/jordan-lee-code/display-profiles.git
cd display-profiles
```

### 2. Run the installer

```bash
bash install.sh
```

This will:
- Symlink all `bin/display-*.sh` scripts into `~/bin/` (edits to the repo take effect immediately)
- Generate and install `display-shutdown.desktop` into `~/.local/share/applications/`
- Generate and install `display-apply.desktop` into `~/.config/autostart/` (applies saved profile on every login)

### 3. Add `~/bin` to your PATH

Check if it's already there:

```bash
echo $PATH | tr ':' '\n' | grep -q "$HOME/bin" && echo "already in PATH" || echo "not in PATH"
```

If not, add it:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

### 4. Discover your outputs

```bash
display-setup.sh
```

This lists every connected output with its available resolutions and refresh rates, and any profiles already saved. Use this to find the exact output names (`DP-0`, `HDMI-1`, etc.) you'll need when creating profiles.

### 5. Create your first profile

```bash
display-new-profile.sh
```

The wizard walks through:

1. **Profile name** — used as the directory name and in commands, e.g. `work`, `gaming`, `desk`
2. **Enable/disable each output** — connected outputs are listed; disable any you don't want active
3. **Resolution** — available modes for each enabled output, highest first
4. **Refresh rate** — available rates for the chosen resolution
5. **Primary output** — which output is the primary (where panels and dialogs appear by default)
6. **Positions** — for each remaining output, choose placement relative to any already-positioned screen: left, right, above, below, centered-above, or centered-below. With two or more screens placed, centered-above-all and centered-below-all are also offered. An ASCII diagram and pixel coordinate summary are shown before saving.
7. **Start menu shortcut** — optionally creates a `.desktop` launcher so you can switch from the application menu
8. **Panel layout** — if a supported DE is detected, optionally snapshots the current panel configuration into the profile

Example session:

```
Profile name: work
Connected outputs:
  1. DP-0
  2. DP-2
Enable DP-0? [Y/n] n
Enable DP-2? [Y/n]
  Available resolutions:
    1. 2560x1440
    2. 1920x1080
  Select [1]:
  Available refresh rates for 2560x1440:
    1. 165.08Hz
    2. 143.91Hz
  Select [1]:
Profile description (optional): Single screen, right monitor only
Create start menu shortcut? [Y/n]
Save current panel layout for this profile? [Y/n]

Profile 'work' created.
Switch to this profile with: display-switch.sh work
```

The generated profile is stored at `~/.config/display-profiles/work/` and contains:

```
work/
├── xrandr.sh        # the generated xrandr command — plain bash, edit freely
├── panel-layout.sh  # DE panel restore script (if saved)
└── meta             # name, description, created date
```

Repeat `display-new-profile.sh` for each profile you need.

### 6. Save panel layouts (optional)

If you want each profile to restore a specific panel arrangement, switch to the profile, arrange your panels how you want them in the DE, then run:

```bash
display-save-layout.sh <profile>
```

This snapshots the current panel configuration into `panel-layout.sh` inside the profile directory. `display-switch.sh` applies it automatically on every switch.

To update a saved layout, just re-run `display-save-layout.sh <profile>` after rearranging panels.

### 7. Test switching

```bash
display-switch.sh <profile>
```

---

## Daily use

### Switching profiles on the fly

From a terminal:

```bash
display-switch.sh <profile>
```

Or use the start menu shortcuts created during `display-new-profile.sh`.

### Shutdown and restart

`display-shutdown.sh` and `display-restart.sh` show a profile selection dialog before acting — Zenity radiolist if a display is available, terminal `select` menu otherwise. Every profile in `~/.config/display-profiles/` appears automatically.

Use the **Shutdown** entry added to the application menu by `install.sh`, or call the scripts directly.

### Profile applied on login

The autostart entry installed by `install.sh` calls `display-apply-saved.sh` on every login, which reads `~/.config/display-mode` and switches to the last selected profile. No manual intervention needed after selecting a profile at shutdown or restart.

---

## Adding a new profile later

```bash
display-new-profile.sh
```

New profiles appear in the shutdown/restart dialog automatically.

## Editing a profile

Profile xrandr commands are plain bash in `~/.config/display-profiles/<name>/xrandr.sh`. Edit directly:

```bash
nano ~/.config/display-profiles/work/xrandr.sh
```

The generated file looks like this:

```bash
#!/bin/bash
xrandr \
    --output DP-0 --mode 2560x1440 --rate 165.08 --pos 0x0 --primary \
    --output DP-2 --mode 1920x1080 --rate 60.00 --pos 2560x180 \
    --output HDMI-0 --off
```

Common things to change:
- `--rate` — adjust the refresh rate (must be a rate listed by `xrandr` for that mode)
- `--pos XxY` — move an output; `0x0` is top-left, `2560x0` puts it immediately right of a 2560-wide display
- `--mode WxH` — change the resolution

To regenerate from scratch, run `display-new-profile.sh` again with the same name and confirm the overwrite.

## Deleting a profile

```bash
rm -rf ~/.config/display-profiles/<name>
rm -f ~/.local/share/applications/display-<name>.desktop
```

---

## DE support

Panel layout save/restore is handled by hooks in `hooks/<de>/`. Cinnamon is included. To add support for another DE, create two scripts:

**`hooks/<de>/save-panels.sh`** — receives the profile directory as `$1`, writes panel config to `$1/panel-layout.sh`:

```bash
#!/bin/bash
PROFILE_DIR="$1"
# write panel restore commands to $PROFILE_DIR/panel-layout.sh
chmod +x "$PROFILE_DIR/panel-layout.sh"
```

**`hooks/<de>/restart-de.sh`** — reloads the compositor/shell after panel config is applied:

```bash
#!/bin/bash
# e.g. for GNOME:
# busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart()'
```

The DE is detected from `$XDG_CURRENT_DESKTOP`. Supported values: `cinnamon`, `gnome`, `kde`, `xfce`, `mate`.

---

## Cinnamenu integration (optional)

Replace Cinnamenu's built-in shutdown button and add a restart button. Open:

```
~/.local/share/cinnamon/applets/Cinnamenu@json/5.8/sidebar.js
```

Find the shutdown `SidebarButton` block and replace its callback:

```javascript
// Before:
this.appThis.sessionManager.ShutdownRemote();

// After (replace YOUR_USER with your username, e.g. /home/jordan/bin/...):
Util.spawnCommandLine('/home/YOUR_USER/bin/display-shutdown.sh');
```

Add the restart button immediately after the shutdown block:

```javascript
this.items.push(new SidebarButton(
    this.appThis,
    newSidebarIcon('system-reboot'),
    null,
    _('Restart'),
    _('Select display profile and restart'),
    () => {
        this.appThis.menu.close();
        Util.spawnCommandLine('/home/YOUR_USER/bin/display-restart.sh');  // replace YOUR_USER
    }));
```

Reload Cinnamon to apply:

```bash
cinnamon --replace &
```

---

## Scripts reference

| Script | What it does |
|--------|-------------|
| `display-setup.sh` | List connected outputs with available modes and saved profiles |
| `display-new-profile.sh` | Interactive wizard to create a new named profile |
| `display-switch.sh <name>` | Apply a profile (xrandr + panel layout + DE restart if needed) |
| `display-save-layout.sh <name>` | Snapshot current DE panel config into a profile |
| `display-apply-saved.sh` | Apply the last saved profile (used by autostart) |
| `display-shutdown.sh` | Prompt for next profile, save choice, power off |
| `display-restart.sh` | Prompt for next profile, save choice, reboot |

---

## Troubleshooting

**Outputs not switching** — check the output names in your profile match what `xrandr` reports:
```bash
xrandr | grep " connected"
display-setup.sh
```

**Panel layout not restoring** — confirm a `panel-layout.sh` exists in the profile directory and that your DE is detected correctly:
```bash
echo $XDG_CURRENT_DESKTOP
ls ~/.config/display-profiles/<name>/
```

**Refresh rate reverting to 60Hz** — this is the Nvidia driver bug the scripts were built to address. The autostart entry re-applies the profile on every login. If it happens mid-session, run `display-switch.sh <profile>` again.

**Zenity dialog not appearing at shutdown** — ensure `DISPLAY` is set. The scripts export `DISPLAY=:0` as a fallback, but if your display server is on a different display, update the export in `display-shutdown.sh` and `display-restart.sh`.

**`display-switch.sh: command not found`** — `~/bin` is not in your PATH. Add it to `~/.bashrc` as described in the installation steps.

**xrandr command failed** — if a profile applies partially or you see a generic error, check the debug log written by `display-switch.sh`:
```bash
cat ~/.config/display-profiles/debug.log
```
Common causes: output name mismatch (run `display-setup.sh` to verify), mode not supported by the driver, or monitor disconnected.

---

## Contributing

PRs welcome. The most useful additions are DE hooks — if you add support for GNOME, XFCE, or another desktop, the `hooks/<de>/` pattern is all it takes. See the DE support section above.

---

## License

MIT. See [LICENSE](LICENSE).
