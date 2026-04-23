# display-profiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Switch between named display profiles on Linux — applying xrandr configuration, optional DE panel layouts, and persisting the active profile across reboots.

Built to work around the Nvidia driver bug that drops refresh rate and forgets display arrangement after mode changes, and for use with software KVMs like [Barrier](https://github.com/debauchee/barrier) where switching between work and personal use requires a different monitor layout each time.

## What it does

- Applies `xrandr` config (outputs, resolution, refresh rate, positions, primary)
- Saves and restores DE panel layouts per profile (Cinnamon supported; hooks for others)
- Applies the saved profile automatically on login via autostart
- Interactive wizard to create new profiles with output discovery
- GTK3 system tray applet for point-and-click switching and profile management

---

## Requirements

| Package | Purpose | Required |
|---------|---------|----------|
| `x11-xserver-utils` | Provides `xrandr` | Yes |
| `dconf-tools` | Panel layout save/restore | Cinnamon only |

Install on Debian/Ubuntu/Mint:

```bash
sudo apt install x11-xserver-utils dconf-tools
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

The easiest way is the system tray applet — click a profile name to switch immediately. Alternatively, from a terminal:

```bash
display-switch.sh <profile>
```

Or use the start menu shortcuts created during `display-new-profile.sh`.

### Profile applied on login

On every login, `display-apply-saved.sh` reads `~/.config/display-mode` and switches to whichever profile is recorded there. That file is updated whenever you switch profiles, or when you use **Profile for next login** in the tray applet to pre-select a different layout for the next login without changing your current display.

---

## Adding a new profile later

```bash
display-new-profile.sh
```

New profiles appear in the tray applet automatically.

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

## Scripts reference

| Script | What it does |
|--------|-------------|
| `display-setup.sh` | List connected outputs with available modes and saved profiles |
| `display-new-profile.sh` | Interactive wizard to create a new named profile |
| `display-switch.sh <name>` | Apply a profile (xrandr + panel layout + DE restart if needed) |
| `display-save-layout.sh <name>` | Snapshot current DE panel config into a profile |
| `display-apply-saved.sh` | Apply the last saved profile (used by autostart) |

---

## System tray applet

`gui/display-profiles-tray.py` is a GTK3 system tray applet that gives you a point-and-click interface for everything in the scripts.

**Requirements:** `python3-gi`, plus either `gir1.2-ayatanaappindicator3-0.1` (recommended) or `gir1.2-appindicator3-0.1`:

```bash
sudo apt install python3-gi gir1.2-ayatanaappindicator3-0.1
```

**Run it:**

```bash
python3 gui/display-profiles-tray.py
```

**Menu reference:**

| Entry | What it does |
|-------|-------------|
| Profile names (top section) | Switch to that profile immediately — same as `display-switch.sh <name>` |
| **Launch tray on login** | Adds/removes an XDG autostart entry so the tray starts with your session |
| **Auto-apply profile on login** | Adds/removes an XDG autostart entry that runs `display-apply-saved.sh` on every login. When enabled, whatever profile is recorded in `~/.config/display-mode` will be applied automatically after you log in |
| **Profile for next login** | Submenu — select a profile to record in `~/.config/display-mode` *without* switching your current display. Greyed out when auto-apply is off. Use this to pre-select a different profile before you log out |
| **New profile…** | Opens the profile creation wizard |

**How auto-apply works end-to-end:**

1. `~/.config/display-mode` holds a single line: the name of the profile to apply at login
2. `display-switch.sh` updates this file every time you switch profiles
3. "Profile for next login" in the tray updates it without switching anything — useful when you want to log out and come back in a different layout
4. On login, `display-apply-saved.sh` reads the file and calls `display-switch.sh` with that name

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

**`display-switch.sh: command not found`** — `~/bin` is not in your PATH. Add it to `~/.bashrc` as described in the installation steps.

**xrandr command failed** — if a profile applies partially or you see a generic error, check the debug log written by `display-switch.sh`:

```bash
cat ~/.config/display-profiles/debug.log
```

Common causes: output name mismatch (run `display-setup.sh` to verify), mode not supported by the driver, or monitor disconnected.

---

## Running the tests

```bash
bash tests/validate.sh
```

Covers bash syntax across all scripts, unit tests for every `lib/common.sh` function, error-path behaviour for each script, and a live round-trip display switch (re-applies the current config via xrandr). Sections that require a running X session are skipped automatically when `DISPLAY` is not set.

---

## Contributing

PRs welcome. The most useful additions are DE hooks — if you add support for GNOME, XFCE, or another desktop, the `hooks/<de>/` pattern is all it takes. See the DE support section above.

---

## License

MIT. See [LICENSE](LICENSE).
