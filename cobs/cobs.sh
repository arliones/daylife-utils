#!/usr/bin/env bash
# Opens Obsidian (if it is not running yet) and starts a fresh Claude Code
# session inside the Obsidian vault.
#
# Once Obsidian is running, both windows are arranged on the largest monitor:
# Obsidian takes the left two thirds, and the terminal this script was called
# from takes the right third.
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
import sys, time
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

wa = biggest_monitor_workarea()
obsidian_w = round(wa.width * 2 / 3)
terminal_w = wa.width - obsidian_w

if obsidian is not None:
    place(obsidian, wa.x, wa.y, obsidian_w, wa.height)
if terminal is not None:
    place(terminal, wa.x + obsidian_w, wa.y, terminal_w, wa.height)
    # A freshly started Obsidian steals the focus; give it back to the terminal.
    terminal.activate(server_time())
    pump()
PY
}

arrange_windows || echo "warning: could not arrange the windows." >&2

cd "$VAULT_DIR"
exec claude
