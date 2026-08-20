# codes

**codes** opens [VS Code](https://code.visualstudio.com) in the current directory, tiles it
side by side with the terminal, and starts a [Claude Code](https://claude.com/claude-code)
session in that terminal — with a single command.

## Description

Running `codes.sh` from a directory does three things:

1. Starts `code <dir>` for the directory the command was run from (or focuses the matching
   window if VS Code already has it open).
2. Arranges the windows on the largest monitor: VS Code on the left two thirds, and the
   terminal the command was typed in on the right third. Focus is given back to the terminal
   afterwards, since VS Code steals it when a window is opened or focused.
3. Replaces itself with a Claude Code session in that same terminal, in the same directory.

The terminal window is identified once, right when the script starts — before VS Code has a
chance to open and steal focus — as whichever window is currently active, cross-checked against
the ancestor PIDs of the script itself (so it also works if the active-window check is
inconclusive, e.g. under terminal emulators such as GNOME Terminal that run every window behind
a single shared server process). The VS Code window is identified by matching its window class
together with the target directory's name in the window title, so an already-open window for
that folder is reused instead of spawning a duplicate. The monitor is picked by area, and its
*work area* is used, so panels and docks are accounted for automatically.

The exact split may be off by a few pixels for terminals that only resize in whole character
cells (GNOME Terminal, for one). The leftover pixels are left at the outer edge of the screen,
not between the windows.

If the window arrangement fails for any reason, a warning is printed and the script exits
without touching the windows further.

## Dependencies

- **Bash**
- **X11 session** — the arrangement is skipped under Wayland, where libwnck cannot manage
  other applications' windows
- **python3-gi** with the Wnck and GdkX11 typelibs (usually already installed on GNOME):
  ```sh
  sudo apt install python3-gi gir1.2-wnck-3.0
  ```
- **code** (VS Code) and **claude** (Claude Code) available in your PATH

## Installation

```sh
./install.sh
```

This symlinks `codes.sh` into `~/bin`, so a `git pull` in this repository is enough to update
the installed command. Use `BIN_DIR=~/.local/bin ./install.sh` to link it somewhere else.

## Uninstallation

```sh
./uninstall.sh
```

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `CODES_NO_LAYOUT` | unset | Set to `1` to skip the window arrangement |
| `CODES_LAYOUT_TIMEOUT` | `20` | Seconds to wait for the VS Code window |
| `CODES_DEBUG` | unset | Set to `1` to print window-matching diagnostics to stderr |

---

**Author:** Arliones Hoeller Jr.<br>
**License:** MIT
