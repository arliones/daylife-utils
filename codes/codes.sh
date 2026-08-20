#!/usr/bin/env bash
# Opens VS Code in the directory this script was called from, arranges the
# windows on the largest monitor (VS Code on the left two thirds, the
# terminal this script was called from on the right third), and starts a
# Claude Code session in that same terminal.
#
# Environment variables:
#   CODES_NO_LAYOUT=1        skip the window arrangement
#   CODES_LAYOUT_TIMEOUT=20  seconds to wait for the VS Code window to show up
#   CODES_DEBUG=1            print window-matching diagnostics to stderr
set -euo pipefail

TARGET_DIR="$(pwd)"

# PIDs of this shell and all of its ancestors — this is how the terminal
# window is identified, since the terminal emulator is one of those ancestors.
pid_ancestors() {
    local p=$$
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        echo "$p"
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)
    done
}

arrange_windows() {
    if [ "${CODES_NO_LAYOUT:-0}" = 1 ]; then
        return 0
    fi
    if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
        echo "warning: not an X11 session, skipping the window arrangement." >&2
        return 0
    fi
    python3 - "${CODES_LAYOUT_TIMEOUT:-20}" "$TARGET_DIR" "${CODES_DEBUG:-0}" $(pid_ancestors) <<'PY'
import os, subprocess, sys, time
import gi
gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkX11", "3.0")
gi.require_version("Wnck", "3.0")
from gi.repository import Gdk, GdkX11, Gtk, Wnck

TIMEOUT = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
TARGET_DIR = sys.argv[2]
DEBUG = sys.argv[3] == "1"
ANCESTORS = {int(p) for p in sys.argv[4:]}
BASENAME = os.path.basename(TARGET_DIR.rstrip("/")) or TARGET_DIR


def debug(*args):
    if DEBUG:
        print("[codes debug]", *args, file=sys.stderr)


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


def is_code(win):
    name = (win.get_class_group_name() or "") + " " + (win.get_class_instance_name() or "")
    return "code" in name.lower()


def normal_windows(screen):
    screen.force_update()
    pump()
    return [w for w in screen.get_windows() if w.get_window_type() == Wnck.WindowType.NORMAL]


def dump_windows(label, wins, active):
    if not DEBUG:
        return
    debug(f"{label}: ancestors={sorted(ANCESTORS)}")
    for w in wins:
        debug(
            f"  pid={w.get_pid()} class={w.get_class_group_name()!r}"
            f" name={w.get_name()!r} active={w is active}"
        )


def resolve_terminal(screen):
    """Identify the terminal window this script was launched from.

    Done once, up front, before VS Code has a chance to steal focus: at this
    point whatever window is active is almost certainly the terminal. If the
    active window can't be trusted (e.g. the script was not launched
    interactively) we fall back to PID matching, picking the topmost window
    among the candidates by stacking order — plain PID matching alone is not
    enough because terminal emulators such as GNOME Terminal run every
    window behind a single shared server process, so more than one window
    can share the same PID.
    """
    wins = normal_windows(screen)
    mine = [w for w in wins if w.get_pid() in ANCESTORS]
    active = screen.get_active_window()
    dump_windows("resolving terminal", wins, active)
    if active is not None and (active in mine or not mine):
        return active
    if mine:
        stacked = [w for w in screen.get_windows_stacked() if w in mine]
        return stacked[-1] if stacked else mine[0]
    return None


def find_code_window(screen):
    wins = normal_windows(screen)
    active = screen.get_active_window()
    candidates = [w for w in wins if is_code(w) and BASENAME.lower() in (w.get_name() or "").lower()]
    dump_windows("looking for VS Code window", wins, active)
    if active in candidates:
        return active
    if candidates:
        return candidates[0]
    return None


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
terminal = resolve_terminal(screen)
debug(f"resolved terminal: {terminal.get_name() if terminal else None!r}")

try:
    subprocess.Popen(
        ["code", TARGET_DIR],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
except FileNotFoundError:
    print("warning: 'code' was not found in PATH.", file=sys.stderr)

deadline = time.time() + TIMEOUT
code = find_code_window(screen)
while code is None and time.time() < deadline:
    time.sleep(0.5)
    code = find_code_window(screen)

if terminal is None:
    print("warning: terminal window not found.", file=sys.stderr)
if code is None:
    print("warning: the VS Code window did not show up in time.", file=sys.stderr)
if code is None and terminal is None:
    sys.exit(1)

wa = biggest_monitor_workarea()
code_w = round(wa.width * 2 / 3)
terminal_w = wa.width - code_w

if code is not None:
    place(code, wa.x, wa.y, code_w, wa.height)
if terminal is not None:
    place(terminal, wa.x + code_w, wa.y, terminal_w, wa.height)
    # VS Code steals the focus when it opens/updates; give it back to the
    # terminal afterwards.
    terminal.activate(server_time())
    pump()
PY
}

arrange_windows || echo "warning: could not arrange the windows." >&2

exec claude
