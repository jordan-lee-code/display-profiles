#!/usr/bin/env python3
"""
display-profiles-tray — GTK3 system tray applet for display-profiles.

Tray menu:  list saved profiles (✓ marks the active one), switch by clicking,
            open the creation wizard, or quit.

Wizard:     four-page Gtk.Assistant — profile name, per-output resolution/rate,
            positioning, then a confirm summary.

Requires:
    sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-appindicator3-0.1
    # or on newer systems: gir1.2-ayatanaappindicator3-0.1
"""

import gi
gi.require_version("Gtk", "3.0")

# Support both the Ayatana fork (newer Ubuntu/Mint) and classic AppIndicator3.
_indicator_mod = None
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as _indicator_mod
except (ValueError, ImportError):
    try:
        gi.require_version("AppIndicator3", "0.1")
        from gi.repository import AppIndicator3 as _indicator_mod
    except (ValueError, ImportError):
        pass

from gi.repository import Gtk, GLib, Gio

import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────

PROFILES_DIR       = Path.home() / ".config" / "display-profiles"
DISPLAY_MODE       = Path.home() / ".config" / "display-mode"
AUTOSTART_FILE     = Path.home() / ".config" / "autostart" / "display-apply.desktop"
REPO_DIR           = Path(__file__).resolve().parent.parent
BIN_DIR            = REPO_DIR / "bin"
HOOKS_DIR          = REPO_DIR / "hooks"
AUTOSTART_TEMPLATE = REPO_DIR / "desktop" / "display-apply.desktop"

# ── xrandr parsing ────────────────────────────────────────────────────────────

def parse_xrandr():
    """Return a list of dicts, one per connected output.

    Each dict:
        name       str        output name (e.g. "DP-0")
        active     bool       currently has a geometry / is switched on
        primary    bool       marked as primary by xrandr
        pos_x/y    int        current top-left pixel position
        modes      list[dict] available modes, each:
                       res         "WxH"
                       rates       [str, ...]  all available rates
                       current     str|None    rate currently active (marked *)
    """
    try:
        raw = subprocess.check_output(
            ["xrandr"], text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    outputs = []
    cur = None
    for line in raw.splitlines():
        header = re.match(r'^(\S+)\s+(connected|disconnected)', line)
        if header:
            if header.group(2) == "connected":
                geo = re.search(r'(\d+x\d+)\+(\d+)\+(\d+)', line)
                cur = dict(
                    name    = header.group(1),
                    active  = bool(geo),
                    primary = "primary" in line,
                    pos_x   = int(geo.group(2)) if geo else 0,
                    pos_y   = int(geo.group(3)) if geo else 0,
                    modes   = [],
                )
                outputs.append(cur)
            else:
                cur = None
            continue

        if cur is None:
            continue

        mode_line = re.match(r'^\s+(\d+x\d+)\s+(.*)', line)
        if mode_line:
            res, rest = mode_line.group(1), mode_line.group(2)
            rates, current_rate = [], None
            for token in rest.split():
                clean = re.sub(r'[*+]', '', token)
                if re.match(r'^\d+\.\d+$', clean):
                    if '*' in token:
                        current_rate = clean
                    rates.append(clean)
            if rates:
                cur["modes"].append(
                    dict(res=res, rates=rates, current=current_rate))

    return outputs


# ── Profile I/O ───────────────────────────────────────────────────────────────

def list_profiles():
    """Return sorted list of profile names that have a valid xrandr.sh."""
    if not PROFILES_DIR.exists():
        return []
    return sorted(
        d.name for d in PROFILES_DIR.iterdir()
        if d.is_dir() and (d / "xrandr.sh").exists()
    )


def active_profile():
    """Return the name stored in ~/.config/display-mode, or None."""
    try:
        return DISPLAY_MODE.read_text().strip() or None
    except FileNotFoundError:
        return None


def autostart_enabled():
    """Return True if the display-apply autostart entry is present and enabled."""
    if not AUTOSTART_FILE.exists():
        return False
    return "X-GNOME-Autostart-enabled=true" in AUTOSTART_FILE.read_text()


def set_autostart(enabled):
    """Enable or disable the display-apply autostart entry.

    Creates the desktop file from the repo template if it does not exist yet.
    Toggles X-GNOME-Autostart-enabled rather than deleting the file so the
    user's Exec path is preserved across enable/disable cycles.
    """
    if not AUTOSTART_FILE.exists():
        template = AUTOSTART_TEMPLATE.read_text().replace(
            "%%HOME%%", str(Path.home()))
        AUTOSTART_FILE.parent.mkdir(parents=True, exist_ok=True)
        AUTOSTART_FILE.write_text(template)

    text = AUTOSTART_FILE.read_text()
    if enabled:
        text = text.replace("X-GNOME-Autostart-enabled=false",
                            "X-GNOME-Autostart-enabled=true")
    else:
        text = text.replace("X-GNOME-Autostart-enabled=true",
                            "X-GNOME-Autostart-enabled=false")
    AUTOSTART_FILE.write_text(text)


def switch_profile(name, parent=None):
    """Run display-switch.sh for the named profile. Shows an error dialog on failure."""
    script = BIN_DIR / "display-switch.sh"
    try:
        subprocess.run(["bash", str(script), name], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError as exc:
        msg = exc.stderr.decode().strip() if exc.stderr else str(exc)
        dlg = Gtk.MessageDialog(
            transient_for=parent,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=f"Failed to switch to '{name}'",
        )
        dlg.format_secondary_text(msg)
        dlg.run()
        dlg.destroy()
        return False


def write_profile(name, outputs, primary, placements, desc=""):
    """Write xrandr.sh and meta into the profile directory.

    Args:
        name        Profile directory name (spaces already replaced with dashes).
        outputs     [{"name": str, "res": "WxH", "rate": str, "enabled": bool}]
        primary     str — name of the primary output.
        placements  {"output_name": ("placement_key", "ref_output_name")}
                    for every non-primary enabled output.
                    Placement keys: right, left, below, above, center-below, center-above
        desc        Human-readable description (optional).
    """
    # Compute absolute pixel positions. Primary is anchored at (0, 0);
    # each other output is placed relative to whichever output the user chose.
    # We iterate enabled outputs in order so that an output can safely reference
    # one that was placed earlier in the same list.
    positions = {primary: (0, 0)}
    enabled = [o for o in outputs if o["enabled"]]

    for o in enabled:
        if o["name"] == primary:
            continue
        placement_key, ref_name = placements[o["name"]]
        ref_x, ref_y = positions[ref_name]
        ref_out  = next(x for x in enabled if x["name"] == ref_name)
        ref_w, ref_h = (int(v) for v in ref_out["res"].split("x"))
        out_w, out_h = (int(v) for v in o["res"].split("x"))

        if   placement_key == "right":        x, y = ref_x + ref_w,                    ref_y
        elif placement_key == "left":         x, y = ref_x - out_w,                    ref_y
        elif placement_key == "below":        x, y = ref_x,                            ref_y + ref_h
        elif placement_key == "above":        x, y = ref_x,                            ref_y - out_h
        elif placement_key == "center-below": x, y = ref_x + (ref_w - out_w) // 2,    ref_y + ref_h
        elif placement_key == "center-above": x, y = ref_x + (ref_w - out_w) // 2,    ref_y - out_h
        else:                                 x, y = ref_x + ref_w,                    ref_y

        positions[o["name"]] = (x, y)

    # Shift so the top-left corner of the whole layout is (0, 0).
    if positions:
        min_x = min(x for x, _ in positions.values())
        min_y = min(y for _, y in positions.values())
        positions = {k: (x - min_x, y - min_y) for k, (x, y) in positions.items()}

    # Write files.
    profile_dir = PROFILES_DIR / name
    profile_dir.mkdir(parents=True, exist_ok=True)

    parts = ["xrandr"]
    for o in outputs:
        if o["enabled"]:
            px, py = positions[o["name"]]
            part = (f"--output {o['name']} --mode {o['res']} "
                    f"--rate {o['rate']} --pos {px}x{py}")
            if o["name"] == primary:
                part += " --primary"
        else:
            part = f"--output {o['name']} --off"
        parts.append("    " + part)

    xrandr_sh = profile_dir / "xrandr.sh"
    xrandr_sh.write_text("#!/bin/bash\n" + " \\\n".join(parts) + "\n")
    xrandr_sh.chmod(0o755)

    created = datetime.now(timezone.utc).astimezone().isoformat()
    (profile_dir / "meta").write_text(
        f"NAME={name}\nDESCRIPTION={desc}\nCREATED={created}\n"
    )

    # Optionally snapshot the current DE panel layout.
    xdg = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    desktop = os.environ.get("DESKTOP_SESSION", "").lower()
    combined = xdg + " " + desktop
    if   "cinnamon" in combined: de = "cinnamon"
    elif "gnome"    in combined: de = "gnome"
    elif "kde"      in combined or "plasma" in combined: de = "kde"
    elif "xfce"     in combined: de = "xfce"
    elif "mate"     in combined: de = "mate"
    else:                        de = "unknown"

    hook = HOOKS_DIR / de / "save-panels.sh"
    if hook.exists():
        subprocess.run(["bash", str(hook), str(profile_dir)], capture_output=True)


# ── Profile creation wizard ────────────────────────────────────────────────────

# (placement_key, display_label) pairs shown in the positioning dropdowns.
PLACEMENTS = [
    ("right",         "Right of"),
    ("left",          "Left of"),
    ("below",         "Below"),
    ("above",         "Above"),
    ("center-below",  "Centred below"),
    ("center-above",  "Centred above"),
]


class ProfileWizard(Gtk.Assistant):
    """Four-page assistant for creating a new display profile."""

    def __init__(self, parent=None, on_created=None):
        super().__init__(transient_for=parent, title="New Display Profile")
        self.set_default_size(600, 460)
        self.set_modal(True)
        self.on_created = on_created

        self._xrandr = parse_xrandr()

        # Widgets read at Apply time — populated in _build_pages().
        self._name_entry     = None
        self._desc_entry     = None
        self._output_rows    = []   # [{"output", "check", "res_combo", "rate_combo"}]
        self._primary_combo  = None
        self._placement_grid = None
        self._placement_rows = []   # [{"name", "placement_combo", "ref_combo", "widgets"}]
        self._summary_label  = None
        self._confirm_box    = None
        self._position_box   = None

        self._build_pages()
        self.connect("apply",  self._on_apply)
        self.connect("cancel", lambda w: w.destroy())
        self.connect("close",  lambda w: w.destroy())
        self.connect("prepare", self._on_prepare)
        self.show_all()

    # ── Page builders ──────────────────────────────────────────────────────────

    def _build_pages(self):
        self._add_name_page()
        self._add_outputs_page()
        self._add_position_page()
        self._add_confirm_page()

    def _add_name_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_border_width(24)

        heading = Gtk.Label(use_markup=True,
                            label="<big><b>New display profile</b></big>",
                            halign=Gtk.Align.START)
        box.pack_start(heading, False, False, 0)

        grid = Gtk.Grid(row_spacing=10, column_spacing=12)

        grid.attach(Gtk.Label(label="Profile name:", halign=Gtk.Align.END), 0, 0, 1, 1)
        self._name_entry = Gtk.Entry(placeholder_text="e.g. desk-dual", hexpand=True)
        self._name_entry.connect("changed", self._on_name_changed)
        grid.attach(self._name_entry, 1, 0, 1, 1)

        grid.attach(Gtk.Label(label="Description:", halign=Gtk.Align.END), 0, 1, 1, 1)
        self._desc_entry = Gtk.Entry(placeholder_text="Optional", hexpand=True)
        grid.attach(self._desc_entry, 1, 1, 1, 1)

        box.pack_start(grid, False, False, 0)

        if not self._xrandr:
            warn = Gtk.Label(
                label="⚠  No connected outputs detected. Is DISPLAY set?",
                halign=Gtk.Align.START)
            warn.get_style_context().add_class("warning")
            box.pack_start(warn, False, False, 0)

        self.append_page(box)
        self.set_page_type(box,     Gtk.AssistantPageType.INTRO)
        self.set_page_title(box,    "Profile name")
        self.set_page_complete(box, False)

    def _on_name_changed(self, entry):
        complete = bool(entry.get_text().strip())
        self.set_page_complete(self.get_nth_page(0), complete)

    def _add_outputs_page(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        outer.set_border_width(16)

        outer.pack_start(
            Gtk.Label(label="Enable each output and choose a resolution and refresh rate.",
                      halign=Gtk.Align.START, wrap=True),
            False, False, 0)

        grid = Gtk.Grid(row_spacing=8, column_spacing=14)
        grid.set_border_width(4)

        for col, text in enumerate(["Enable", "Output", "Resolution", "Rate (Hz)"]):
            lbl = Gtk.Label(label=f"<b>{text}</b>", use_markup=True,
                            halign=Gtk.Align.START)
            grid.attach(lbl, col, 0, 1, 1)

        self._output_rows = []
        for row_i, out in enumerate(self._xrandr, start=1):
            has_modes = bool(out["modes"])

            check = Gtk.CheckButton()
            check.set_active(out["active"] and has_modes)
            check.set_sensitive(has_modes)
            grid.attach(check, 0, row_i, 1, 1)

            grid.attach(
                Gtk.Label(label=out["name"], halign=Gtk.Align.START),
                1, row_i, 1, 1)

            res_combo = Gtk.ComboBoxText()
            for mode in out["modes"]:
                res_combo.append_text(mode["res"])
            if out["modes"]:
                res_combo.set_active(0)
            res_combo.set_sensitive(check.get_active())
            grid.attach(res_combo, 2, row_i, 1, 1)

            rate_combo = Gtk.ComboBoxText()
            self._fill_rates(rate_combo, out, 0)
            rate_combo.set_sensitive(check.get_active())
            grid.attach(rate_combo, 3, row_i, 1, 1)

            res_combo.connect("changed",  self._on_res_changed,     out, rate_combo)
            check.connect(    "toggled",  self._on_output_toggled,  res_combo, rate_combo)

            self._output_rows.append(
                dict(output=out, check=check, res_combo=res_combo, rate_combo=rate_combo))

        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,
                                     vscrollbar_policy=Gtk.PolicyType.AUTOMATIC)
        scroll.add(grid)
        outer.pack_start(scroll, True, True, 0)

        self.append_page(outer)
        self.set_page_type(outer,     Gtk.AssistantPageType.CONTENT)
        self.set_page_title(outer,    "Outputs")
        self.set_page_complete(outer, True)

    def _fill_rates(self, combo, out, mode_idx):
        combo.remove_all()
        if not out["modes"] or mode_idx >= len(out["modes"]):
            return
        for rate in out["modes"][mode_idx]["rates"]:
            combo.append_text(rate)
        combo.set_active(0)

    def _on_res_changed(self, res_combo, out, rate_combo):
        self._fill_rates(rate_combo, out, res_combo.get_active())

    def _on_output_toggled(self, check, res_combo, rate_combo):
        active = check.get_active()
        res_combo.set_sensitive(active)
        rate_combo.set_sensitive(active)

    def _add_position_page(self):
        self._position_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self._position_box.set_border_width(16)

        self._position_box.pack_start(
            Gtk.Label(label="Set the primary output and position each additional screen.",
                      halign=Gtk.Align.START, wrap=True),
            False, False, 0)

        self._position_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._position_box.pack_start(self._position_content, True, True, 0)

        self.append_page(self._position_box)
        self.set_page_type(self._position_box,     Gtk.AssistantPageType.CONTENT)
        self.set_page_title(self._position_box,    "Positioning")
        self.set_page_complete(self._position_box, True)

    def _rebuild_position_page(self):
        """Reconstruct positioning widgets from current output selections."""
        for child in self._position_content.get_children():
            self._position_content.remove(child)
        self._placement_rows = []
        self._primary_combo  = None

        enabled_names = [
            r["output"]["name"] for r in self._output_rows if r["check"].get_active()
        ]

        if not enabled_names:
            self._position_content.pack_start(
                Gtk.Label(label="No outputs are enabled — go back and enable at least one."),
                False, False, 0)
            self._position_content.show_all()
            return

        # Primary selector
        primary_grid = Gtk.Grid(row_spacing=8, column_spacing=12)
        primary_grid.attach(
            Gtk.Label(label="Primary output:", halign=Gtk.Align.END), 0, 0, 1, 1)
        self._primary_combo = Gtk.ComboBoxText()
        for n in enabled_names:
            self._primary_combo.append_text(n)
        self._primary_combo.set_active(0)
        primary_grid.attach(self._primary_combo, 1, 0, 1, 1)
        self._position_content.pack_start(primary_grid, False, False, 0)

        if len(enabled_names) > 1:
            self._position_content.pack_start(Gtk.Separator(), False, False, 4)

            self._placement_grid = Gtk.Grid(row_spacing=8, column_spacing=14)
            for col, text in enumerate(["Output", "Placement", "Relative to"]):
                self._placement_grid.attach(
                    Gtk.Label(label=f"<b>{text}</b>", use_markup=True,
                              halign=Gtk.Align.START),
                    col, 0, 1, 1)

            self._position_content.pack_start(self._placement_grid, False, False, 0)
            self._primary_combo.connect(
                "changed", self._on_primary_changed, enabled_names)
            self._fill_placement_rows(enabled_names, enabled_names[0])

        self._position_content.show_all()

    def _on_primary_changed(self, combo, enabled_names):
        self._fill_placement_rows(enabled_names, combo.get_active_text())
        self._placement_grid.show_all()

    def _fill_placement_rows(self, enabled_names, primary):
        # Remove previous non-header rows.
        for row in self._placement_rows:
            for w in row["widgets"]:
                self._placement_grid.remove(w)
        self._placement_rows = []

        for row_i, name in enumerate(
                (n for n in enabled_names if n != primary), start=1):

            name_lbl = Gtk.Label(label=name, halign=Gtk.Align.START)
            self._placement_grid.attach(name_lbl, 0, row_i, 1, 1)

            placement_combo = Gtk.ComboBoxText()
            for _, label in PLACEMENTS:
                placement_combo.append_text(label)
            placement_combo.set_active(0)
            self._placement_grid.attach(placement_combo, 1, row_i, 1, 1)

            # Reference can be the primary or any output already added above.
            ref_combo = Gtk.ComboBoxText()
            for ref in [primary] + [r["name"] for r in self._placement_rows]:
                ref_combo.append_text(ref)
            ref_combo.set_active(0)
            self._placement_grid.attach(ref_combo, 2, row_i, 1, 1)

            self._placement_rows.append(dict(
                name=name,
                placement_combo=placement_combo,
                ref_combo=ref_combo,
                widgets=[name_lbl, placement_combo, ref_combo],
            ))

    def _add_confirm_page(self):
        self._confirm_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self._confirm_box.set_border_width(24)

        self._confirm_box.pack_start(
            Gtk.Label(label="Review and click <b>Apply</b> to save the profile.",
                      use_markup=True, halign=Gtk.Align.START, wrap=True),
            False, False, 0)

        self._confirm_box.pack_start(Gtk.Separator(), False, False, 4)

        self._summary_label = Gtk.Label(halign=Gtk.Align.START, wrap=True)
        self._confirm_box.pack_start(self._summary_label, False, False, 0)

        self.append_page(self._confirm_box)
        self.set_page_type(self._confirm_box,     Gtk.AssistantPageType.CONFIRM)
        self.set_page_title(self._confirm_box,    "Confirm")
        self.set_page_complete(self._confirm_box, True)

    def _rebuild_summary(self):
        name = self._name_entry.get_text().strip().replace(" ", "-")
        desc = self._desc_entry.get_text().strip()
        lines = [f"<b>Profile:</b>  {name}"]
        if desc:
            lines.append(f"<b>Description:</b>  {desc}")
        lines.append("")

        for r in self._output_rows:
            if r["check"].get_active():
                res  = r["res_combo"].get_active_text()  or "?"
                rate = r["rate_combo"].get_active_text() or "?"
                lines.append(f"  <b>{r['output']['name']}</b>  {res} @ {rate} Hz")
            else:
                lines.append(f"  {r['output']['name']}  off")

        if self._primary_combo:
            lines.append(f"\n<b>Primary:</b>  {self._primary_combo.get_active_text()}")

        for pr in self._placement_rows:
            placement = pr["placement_combo"].get_active_text() or "?"
            ref       = pr["ref_combo"].get_active_text()       or "?"
            lines.append(f"  <b>{pr['name']}</b>  {placement}  {ref}")

        self._summary_label.set_markup("\n".join(lines))

    # ── Navigation hook ────────────────────────────────────────────────────────

    def _on_prepare(self, assistant, page):
        if page is self._position_box:
            self._rebuild_position_page()
        elif page is self._confirm_box:
            self._rebuild_summary()

    # ── Apply ──────────────────────────────────────────────────────────────────

    def _on_apply(self, assistant):
        name = self._name_entry.get_text().strip().replace(" ", "-")
        desc = self._desc_entry.get_text().strip()

        outputs = [
            dict(
                name    = r["output"]["name"],
                res     = r["res_combo"].get_active_text()  or "",
                rate    = r["rate_combo"].get_active_text() or "",
                enabled = r["check"].get_active(),
            )
            for r in self._output_rows
        ]

        primary = (self._primary_combo.get_active_text()
                   if self._primary_combo
                   else (outputs[0]["name"] if outputs else ""))

        placements = {}
        for pr in self._placement_rows:
            label = pr["placement_combo"].get_active_text() or PLACEMENTS[0][1]
            key   = next((k for k, l in PLACEMENTS if l == label), "right")
            ref   = pr["ref_combo"].get_active_text() or primary
            placements[pr["name"]] = (key, ref)

        write_profile(name, outputs, primary, placements, desc)

        if self.on_created:
            self.on_created(name)


# ── System tray applet ────────────────────────────────────────────────────────

class TrayApp:
    def __init__(self):
        PROFILES_DIR.mkdir(parents=True, exist_ok=True)
        self._wizard = None

        if _indicator_mod is None:
            self._run_fallback()
            return

        self._indicator = _indicator_mod.Indicator.new(
            "display-profiles",
            "video-display-symbolic",
            _indicator_mod.IndicatorCategory.HARDWARE,
        )
        self._indicator.set_status(_indicator_mod.IndicatorStatus.ACTIVE)

        self._menu = Gtk.Menu()
        self._indicator.set_menu(self._menu)
        self._rebuild_menu()

        # Watch the profiles directory so the menu updates if profiles are
        # added or removed by another process.
        monitor = Gio.File.new_for_path(str(PROFILES_DIR)).monitor_directory(
            Gio.FileMonitorFlags.NONE, None)
        monitor.connect("changed", lambda *_: GLib.idle_add(self._rebuild_menu))
        self._dir_monitor = monitor  # keep a reference or GC will destroy it

    def _rebuild_menu(self):
        for item in self._menu.get_children():
            self._menu.remove(item)

        profiles = list_profiles()
        current  = active_profile()

        if profiles:
            for name in profiles:
                label = ("✓  " if name == current else "    ") + name
                item  = Gtk.MenuItem(label=label)
                item.connect("activate", self._on_switch, name)
                self._menu.append(item)
        else:
            empty = Gtk.MenuItem(label="No profiles saved")
            empty.set_sensitive(False)
            self._menu.append(empty)

        self._menu.append(Gtk.SeparatorMenuItem())

        # "Apply on login" toggle — enables/disables the autostart entry.
        # A greyed-out label beneath it shows which profile will be restored.
        autostart_item = Gtk.CheckMenuItem(label="Apply on login")
        autostart_item.set_active(autostart_enabled())
        autostart_item.connect("toggled", self._on_autostart_toggled)
        self._menu.append(autostart_item)

        restore_name = active_profile()
        restore_lbl  = Gtk.MenuItem(
            label=f"    restores: {restore_name}" if restore_name else "    (no profile saved yet)")
        restore_lbl.set_sensitive(False)
        self._menu.append(restore_lbl)

        self._menu.append(Gtk.SeparatorMenuItem())

        new_item = Gtk.MenuItem(label="New profile…")
        new_item.connect("activate", self._on_new_profile)
        self._menu.append(new_item)

        self._menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda *_: Gtk.main_quit())
        self._menu.append(quit_item)

        self._menu.show_all()
        return False  # stop GLib.idle_add from repeating

    def _on_switch(self, _item, name):
        switch_profile(name)
        GLib.idle_add(self._rebuild_menu)

    def _on_autostart_toggled(self, item):
        set_autostart(item.get_active())
        GLib.idle_add(self._rebuild_menu)

    def _on_new_profile(self, _item):
        if self._wizard is not None:
            self._wizard.present()
            return
        self._wizard = ProfileWizard(on_created=self._on_profile_created)
        self._wizard.connect("destroy", self._on_wizard_closed)

    def _on_wizard_closed(self, _wizard):
        self._wizard = None

    def _on_profile_created(self, name):
        self._rebuild_menu()

    def _run_fallback(self):
        """Minimal window shown when no AppIndicator library is available."""
        win = Gtk.Window(title="Display Profiles")
        win.set_default_size(320, 160)
        win.set_border_width(16)
        win.connect("destroy", Gtk.main_quit)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

        lbl = Gtk.Label(
            label="AppIndicator3 not found.\n"
                  "Install: <tt>gir1.2-appindicator3-0.1</tt>",
            use_markup=True)
        box.pack_start(lbl, True, True, 0)

        btn = Gtk.Button(label="New profile…")
        btn.connect("clicked", lambda _: ProfileWizard())
        box.pack_start(btn, False, False, 0)

        win.add(box)
        win.show_all()


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    app = TrayApp()
    Gtk.main()


if __name__ == "__main__":
    main()
