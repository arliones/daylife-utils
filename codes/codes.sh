#!/usr/bin/env bash
# Opens VS Code in the directory this script was called from, arranges the
# windows on the largest monitor (VS Code on the left two thirds, the
# terminal this script was called from on the right third), and starts a
# Claude Code session in that same terminal.
#
# The split is done through GNOME/Mutter's own window-tiling (the same
# thing you get from Super+Left / Super+Right, or dragging a window to the
# screen edge), not by just setting raw window geometry — that way it
# reuses (and if needed, updates) whatever split ratio Mutter already
# remembers, so it stays consistent with windows you tile by hand later.
# Requires xdotool; falls back to a plain geometry split (which native
# window snapping won't remember) if it's not installed.
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
import os, shutil, subprocess, sys, time
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
code_w = round(wa.width * 2 / 3)
terminal_w = wa.width - code_w

if not shutil.which("xdotool"):
    print("warning: xdotool not found (sudo apt install xdotool); falling back to "
          "a plain geometry split that native window snapping won't remember.",
          file=sys.stderr)
    if code is not None:
        place(code, wa.x, wa.y, code_w, wa.height)
    if terminal is not None:
        place(terminal, wa.x + code_w, wa.y, terminal_w, wa.height)
        terminal.activate(server_time())
        pump()
elif code is not None and terminal is not None:
    release_stuck_input()
    # Land both windows away from the monitor's edges first, so Mutter treats
    # them as plain floating windows and the native tile action below is a
    # real (memorized) tile rather than a no-op geometry tweak.
    place(code, wa.x + 40, wa.y + 40, max(400, wa.width // 3), max(300, wa.height // 3))
    place(terminal, wa.x + wa.width - max(400, wa.width // 3) - 40, wa.y + 40,
          max(400, wa.width // 3), max(300, wa.height // 3))

    # A first press always yields a plain half/half tile. Pressing the same
    # shortcut again either cycles to a remembered custom ratio (if the user
    # has previously drag-resized a left tile on this monitor — exactly the
    # ratio we want to reuse) or simply un-tiles the window back to floating;
    # there is no in-between, so more than one extra press is pointless and
    # risks leaving the window floating.
    tile(code, "Left")
    _, _, w, _ = xdo_geometry(code.get_xid())
    if not ratio_ok(w, wa.width):
        tile(code, "Left")
        x2, _, _, _ = xdo_geometry(code.get_xid())
        if abs(x2 - wa.x) > 100:  # no longer flush with the left edge: it un-tiled
            tile(code, "Left")

    tile(terminal, "Right")

    _, _, w, _ = xdo_geometry(code.get_xid())
    if not ratio_ok(w, wa.width):
        drag_shared_border(code, terminal, wa.x + code_w, wa.y + wa.height // 2)

    # VS Code steals the focus when it opens/updates; give it back to the
    # terminal afterwards.
    terminal.activate(server_time())
    pump()
else:
    if code is not None:
        place(code, wa.x, wa.y, code_w, wa.height)
    if terminal is not None:
        place(terminal, wa.x + code_w, wa.y, terminal_w, wa.height)
        terminal.activate(server_time())
        pump()
PY
}

arrange_windows || echo "warning: could not arrange the windows." >&2

exec claude
