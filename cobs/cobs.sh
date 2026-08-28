#!/usr/bin/env bash
# Opens Obsidian (if it is not running yet) and starts a fresh Claude Code
# session inside the Obsidian vault.
#
# Once Obsidian is running, both windows are arranged on the largest monitor:
# Obsidian takes the left two thirds, and the terminal this script was called
# from takes the right third. The split is done through GNOME/Mutter's own
# window-tiling (the same thing you get from Super+Left / Super+Right, or
# dragging a window to the screen edge), not by just setting raw window
# geometry — that way it reuses (and if needed, updates) whatever split
# ratio Mutter already remembers, so it stays consistent with windows you
# tile by hand later. Requires xdotool; falls back to a plain geometry split
# (which native window snapping won't remember) if it's not installed.
#
# Environment variables:
#   COBS_VAULT_DIR          vault directory (default: ~/Dropbox/my_life_in_the_cloud)
#   COBS_NO_LAYOUT=1        skip the window arrangement
#   COBS_LAYOUT_TIMEOUT=20  seconds to wait for the Obsidian window to show up
set -euo pipefail

VAULT_DIR="${COBS_VAULT_DIR:-$HOME/Dropbox/my_life_in_the_cloud}"

if ! pgrep -x obsidian >/dev/null; then
    echo "Obsidian is not running. Starting it..."
    nohup obsidian >/dev/null 2>&1 &
    disown
else
    echo "Obsidian is already running."
fi

# PIDs of this shell and all of its ancestors — this is how the terminal window
# is identified, since the terminal emulator is one of those ancestors.
pid_ancestors() {
    local p=$$
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        echo "$p"
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)
    done
}

arrange_windows() {
    if [ "${COBS_NO_LAYOUT:-0}" = 1 ]; then
        return 0
    fi
    if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
        echo "warning: not an X11 session, skipping the window arrangement." >&2
        return 0
    fi
    python3 - "${COBS_LAYOUT_TIMEOUT:-20}" $(pid_ancestors) <<'PY'
import shutil, subprocess, sys, time
import gi
gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkX11", "3.0")
gi.require_version("Wnck", "3.0")
from gi.repository import Gdk, GdkX11, Gtk, Wnck

TIMEOUT = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
ANCESTORS = {int(p) for p in sys.argv[2:]}

Gdk.init([])
display = Gdk.Display.get_default()
if display is None:
    sys.exit("no X11 display available")


def biggest_monitor_workarea():
    best = None
    for i in range(display.get_n_monitors()):
        wa = display.get_monitor(i).get_workarea()
        if best is None or wa.width * wa.height > best.width * best.height:
            best = wa
    return best


def pump():
    while Gtk.events_pending():
        Gtk.main_iteration()


def server_time():
    return GdkX11.x11_get_server_time(Gdk.get_default_root_window())


def is_obsidian(win):
    name = (win.get_class_group_name() or "") + " " + (win.get_class_instance_name() or "")
    return "obsidian" in name.lower()


def find_windows(screen):
    """Return (Obsidian window, terminal window) — either one may be None."""
    screen.force_update()
    pump()
    wins = [w for w in screen.get_windows() if w.get_window_type() == Wnck.WindowType.NORMAL]
    obsidian = next((w for w in wins if is_obsidian(w)), None)

    active = screen.get_active_window()
    mine = [w for w in wins if w.get_pid() in ANCESTORS]
    if active in mine:
        terminal = active
    elif mine:
        terminal = mine[0]
    elif active is not None and not is_obsidian(active):
        terminal = active
    else:
        terminal = None
    return obsidian, terminal


def place(win, x, y, width, height):
    # Unmaximize/unminimize before resizing: the window manager restores the
    # previous geometry asynchronously and would override set_geometry if both
    # were requested at the same time.
    if win.is_minimized():
        win.unminimize(server_time())
    if win.is_maximized() or win.is_maximized_horizontally() or win.is_maximized_vertically():
        win.unmaximize()
        pump()
        time.sleep(0.3)
        pump()
    win.set_geometry(
        Wnck.WindowGravity.STATIC,
        Wnck.WindowMoveResizeMask.X
        | Wnck.WindowMoveResizeMask.Y
        | Wnck.WindowMoveResizeMask.WIDTH
        | Wnck.WindowMoveResizeMask.HEIGHT,
        x, y, width, height,
    )
    pump()


screen = Wnck.Screen.get_default()
deadline = time.time() + TIMEOUT
obsidian, terminal = find_windows(screen)
while obsidian is None and time.time() < deadline:
    time.sleep(0.5)
    obsidian, terminal = find_windows(screen)

if terminal is None:
    print("warning: terminal window not found.", file=sys.stderr)
if obsidian is None:
    print("warning: the Obsidian window did not show up in time.", file=sys.stderr)
if obsidian is None and terminal is None:
    sys.exit(1)

TARGET_RATIO = 2 / 3
RATIO_TOLERANCE = 0.06


def xdo(*args):
    subprocess.run(["xdotool", *args],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)


def release_stuck_input():
    # A previous run interrupted mid-drag/mid-keypress (Ctrl+C, a crash) can
    # leave a key or mouse button logically "held down" as far as the X
    # server is concerned, which silently swallows the native tile shortcuts
    # below. Cheap insurance before relying on them.
    xdo("keyup", "super", "Left", "Right")
    for button in ("1", "2", "3"):
        xdo("mouseup", button)


def xdo_geometry(xid):
    out = subprocess.run(["xdotool", "getwindowgeometry", "--shell", str(xid)],
                          capture_output=True, text=True, timeout=5).stdout
    vals = dict(line.split("=", 1) for line in out.strip().splitlines() if "=" in line)
    return int(vals["X"]), int(vals["Y"]), int(vals["WIDTH"]), int(vals["HEIGHT"])


def ratio_ok(width, monitor_width):
    return abs(width / monitor_width - TARGET_RATIO) < RATIO_TOLERANCE


def tile(win, key):
    win.activate(server_time())
    pump()
    time.sleep(0.2)
    xdo("key", "--clearmodifiers", f"super+{key}")
    time.sleep(0.5)


def drag_shared_border(left_win, right_win, target_x, mid_y):
    """One best-effort attempt to teach Mutter a custom split ratio, by
    replaying the same border-drag gesture a user would do by hand: hover the
    narrow (a few pixels wide) shared edge between two tiled windows, then
    drag it. Mutter remembers whatever ratio this produces and reuses it for
    future native tile operations (keyboard shortcut or edge-drag), which is
    what makes later windows land on the same split. If the drag misses the
    handle, the windows are simply left at whatever tile they already have.
    """
    lx, ly, lw, lh = xdo_geometry(left_win.get_xid())
    rx, ry, rw, rh = xdo_geometry(right_win.get_xid())
    border_x = (lx + lw + rx) // 2
    xdo("mousemove", str(border_x), str(mid_y))
    time.sleep(0.4)
    xdo("mousemove", str(border_x - 2), str(mid_y))
    time.sleep(0.15)
    xdo("mousemove", str(border_x), str(mid_y))
    time.sleep(0.4)
    xdo("mousedown", "1")
    time.sleep(0.3)
    steps = 12
    for i in range(1, steps + 1):
        x = border_x + round((target_x - border_x) * i / steps)
        xdo("mousemove", str(x), str(mid_y))
        time.sleep(0.08)
    time.sleep(0.2)
    xdo("mouseup", "1")
    time.sleep(0.4)


wa = biggest_monitor_workarea()
obsidian_w = round(wa.width * 2 / 3)
terminal_w = wa.width - obsidian_w

if not shutil.which("xdotool"):
    print("warning: xdotool not found (sudo apt install xdotool); falling back to "
          "a plain geometry split that native window snapping won't remember.",
          file=sys.stderr)
    if obsidian is not None:
        place(obsidian, wa.x, wa.y, obsidian_w, wa.height)
    if terminal is not None:
        place(terminal, wa.x + obsidian_w, wa.y, terminal_w, wa.height)
        terminal.activate(server_time())
        pump()
elif obsidian is not None and terminal is not None:
    release_stuck_input()
    # Land both windows away from the monitor's edges first, so Mutter treats
    # them as plain floating windows and the native tile action below is a
    # real (memorized) tile rather than a no-op geometry tweak.
    place(obsidian, wa.x + 40, wa.y + 40, max(400, wa.width // 3), max(300, wa.height // 3))
    place(terminal, wa.x + wa.width - max(400, wa.width // 3) - 40, wa.y + 40,
          max(400, wa.width // 3), max(300, wa.height // 3))

    # A first press always yields a plain half/half tile. Pressing the same
    # shortcut again either cycles to a remembered custom ratio (if the user
    # has previously drag-resized a left tile on this monitor — exactly the
    # ratio we want to reuse) or simply un-tiles the window back to floating;
    # there is no in-between, so more than one extra press is pointless and
    # risks leaving the window floating.
    tile(obsidian, "Left")
    _, _, w, _ = xdo_geometry(obsidian.get_xid())
    if not ratio_ok(w, wa.width):
        tile(obsidian, "Left")
        x2, _, _, _ = xdo_geometry(obsidian.get_xid())
        if abs(x2 - wa.x) > 100:  # no longer flush with the left edge: it un-tiled
            tile(obsidian, "Left")

    tile(terminal, "Right")

    _, _, w, _ = xdo_geometry(obsidian.get_xid())
    if not ratio_ok(w, wa.width):
        drag_shared_border(obsidian, terminal, wa.x + obsidian_w, wa.y + wa.height // 2)

    # A freshly started Obsidian steals the focus; give it back to the terminal.
    terminal.activate(server_time())
    pump()
else:
    if obsidian is not None:
        place(obsidian, wa.x, wa.y, obsidian_w, wa.height)
    if terminal is not None:
        place(terminal, wa.x + obsidian_w, wa.y, terminal_w, wa.height)
        terminal.activate(server_time())
        pump()
PY
}

arrange_windows || echo "warning: could not arrange the windows." >&2

cd "$VAULT_DIR"
exec claude
