# display-profiles

Switch between named display profiles on Linux — applying xrandr configuration, optional DE panel layouts, and persisting the active profile across reboots.

Built to work around the Nvidia driver bug that drops refresh rate and forgets display arrangement after mode changes, and for use with software KVMs like [Barrier](https://github.com/debauchee/barrier) where switching between work and personal use requires a different monitor layout each time.

## What it does

- Applies `xrandr` config (outputs, resolution, refresh rate, positions, primary)
- Saves and restores DE panel layouts per profile (Cinnamon supported; hooks for others)
- Prompts for the next profile at shutdown and restart via a Zenity dialog or terminal menu
- Applies the saved profile automatically on login via autostart
- Interactive wizard to create new profiles with output discovery
- Thin compatibility wrappers so existing shortcuts keep working

## Requirements

- `xrandr` — display configuration (`x11-xserver-utils`)
- `zenity` — GTK dialog for shutdown/restart prompts (optional — falls back to terminal)
- `dconf-tools` — panel layout save/restore (Cinnamon only)

```bash
sudo apt install x11-xserver-utils zenity dconf-tools
```

## Installation

```bash
git clone https://github.com/jordan-lee-code/display-profiles.git
cd display-profiles
bash install.sh
```

Make sure `~/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

## Quick start

```bash
display-setup.sh          # see connected outputs and saved profiles
display-new-profile.sh    # create a new profile interactively
display-switch.sh <name>  # apply a profile
```

## Creating a profile

`display-new-profile.sh` walks through output discovery, resolution and refresh rate selection, primary output, and relative positioning:

```
Profile name: gaming
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
Create start menu shortcut? [Y/n]
Save current panel layout for this profile? [Y/n]
```

Profiles are stored in `~/.config/display-profiles/<name>/` containing:
- `xrandr.sh` — the generated xrandr command
- `panel-layout.sh` — optional DE panel restore script
- `meta` — name, description, created date

## Saving panel layouts

After switching to a profile and arranging panels how you want them:

```bash
display-save-layout.sh <profile>
```

The current DE panel configuration is snapshotted into `panel-layout.sh` inside the profile directory. `display-switch.sh` runs it automatically when switching to that profile.

## Shutdown and restart

`display-shutdown.sh` and `display-restart.sh` prompt for a profile before acting. They use a Zenity radiolist if a display is available, or a terminal `select` menu otherwise. Any profile in `~/.config/display-profiles/` appears as an option automatically.

## DE support

Panel layout save/restore is handled by hooks in `hooks/<de>/`. Cinnamon is supported out of the box. To add support for another DE, create:

- `hooks/<de>/save-panels.sh <profile-dir>` — snapshot current panel config
- `hooks/<de>/restart-de.sh` — reload the compositor

The DE is detected from `$XDG_CURRENT_DESKTOP`.

## Cinnamenu integration (optional)

Replace Cinnamenu's shutdown button and add a restart button in `sidebar.js`:

```javascript
// Find the shutdown SidebarButton and replace its callback:
() => {
    this.appThis.menu.close();
    Util.spawnCommandLine('/home/YOUR_USER/bin/display-shutdown.sh');
}

// Add immediately after (restart button):
this.items.push(new SidebarButton(
    this.appThis,
    newSidebarIcon('system-reboot'),
    null, _('Restart'), _('Select display profile and restart'),
    () => {
        this.appThis.menu.close();
        Util.spawnCommandLine('/home/YOUR_USER/bin/display-restart.sh');
    }));
```

Then reload: `cinnamon --replace &`

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
| `display-work.sh` | Compatibility wrapper for `display-switch.sh work` |
| `display-personal.sh` | Compatibility wrapper for `display-switch.sh personal` |
