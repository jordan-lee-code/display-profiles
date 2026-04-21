# cinnamon-display-profiles

Switch between named display profiles on Linux Mint Cinnamon, with automatic panel layout restore on login.

Built as a workaround for the Nvidia driver bug that intermittently drops refresh rate and forgets display arrangement after mode changes. Also useful for anyone using a software KVM like [Barrier](https://github.com/debauchee/barrier) who needs different monitor configs for work and personal use.

## What it does

- Switches monitor layout with `xrandr` (outputs, positions, refresh rate, primary)
- Saves and restores Cinnamon panel layouts per profile using `dconf`
- Prompts for the next profile before shutdown or restart via a Zenity dialog
- Re-applies the saved profile automatically on every login via autostart
- Adds start menu entries for switching on the fly
- Optionally replaces Cinnamenu's shutdown/restart buttons with the prompted versions

Two profiles are included: **work** (single screen) and **personal** (dual screen). Monitor names, resolution, and panel layout are all configurable.

## Requirements

- Linux Mint Cinnamon (or any Cinnamon-based distro)
- `xrandr` — display configuration
- `zenity` — GTK dialog for shutdown/restart prompts
- `dconf-tools` — panel layout save/restore

```bash
sudo apt install x11-xserver-utils zenity dconf-tools
```

## Installation

```bash
git clone https://github.com/jordan-lee-code/cinnamon-display-profiles.git
cd cinnamon-display-profiles
bash install.sh
```

This copies the scripts to `~/bin/`, installs desktop entries to `~/.local/share/applications/`, and adds the autostart entry to `~/.config/autostart/`.

Make sure `~/bin` is in your PATH. Add this to `~/.bashrc` if not:

```bash
export PATH="$HOME/bin:$PATH"
```

## Configuration

Edit `~/bin/display-work.sh` and `~/bin/display-personal.sh` to match your setup.

**Monitor output names** — find yours with:
```bash
xrandr | grep " connected"
```

**Resolution and refresh rate** — find available modes with:
```bash
xrandr | grep -A20 "DP-0 connected"
```

The defaults in the scripts assume:
| Output | Position | Profile |
|--------|----------|---------|
| DP-0 | Left | Personal primary |
| DP-2 | Right | Work primary (DP-0 off) |

Both at `2560x1440 @ 165.08Hz`.

## Saving panel layouts

After installation, save a layout snapshot for each profile:

```bash
# While in personal mode (both screens up):
display-save-layout.sh personal

# Switch to work mode and arrange the panel, then:
display-save-layout.sh work
```

Snapshots are saved to `~/.config/cinnamon-panels-{work,personal}.sh`. Re-run `display-save-layout.sh` any time you change the panel layout to update the snapshot.

## Cinnamenu integration (optional)

To replace Cinnamenu's built-in shutdown button and add a restart button, edit:

```
~/.local/share/cinnamon/applets/Cinnamenu@json/5.8/sidebar.js
```

Find the shutdown `SidebarButton` and replace the callback:

```javascript
// Replace this:
this.appThis.sessionManager.ShutdownRemote();

// With this:
Util.spawnCommandLine('/home/YOUR_USER/bin/display-shutdown.sh');
```

Add the restart button immediately after the shutdown button block:

```javascript
this.items.push(new SidebarButton(
    this.appThis,
    newSidebarIcon('system-reboot'),
    null,
    _('Restart'),
    _('Select display mode and restart'),
    () => {
        this.appThis.menu.close();
        Util.spawnCommandLine('/home/YOUR_USER/bin/display-restart.sh');
    }));
```

Then reload Cinnamon:

```bash
cinnamon --replace &
```

## Scripts reference

| Script | What it does |
|--------|-------------|
| `display-work.sh` | Apply work profile (xrandr + panel layout + Cinnamon restart) |
| `display-personal.sh` | Apply personal profile (xrandr + panel layout + Cinnamon restart) |
| `display-apply-saved.sh` | Read `~/.config/display-mode` and apply the saved profile |
| `display-save-layout.sh work\|personal` | Snapshot current Cinnamon panel config for the given profile |
| `display-shutdown.sh` | Prompt for next profile, save choice, power off |
| `display-restart.sh` | Prompt for next profile, save choice, reboot |
